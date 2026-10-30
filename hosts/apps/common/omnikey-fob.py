"""OMNIKEY fob scanner: omnikey-fob ingest|lookup (run with sudo).

  ingest  records each fob in Freshservice as a "Key Fob" hardware asset
          (serial number = the embedded PC/SC data), skipping serials
          already there.
  lookup  shows what Freshservice holds for each fob and flags stored
          fields that differ from the scan. Read-only.

The mode has no default: anything else prints usage and exits before any
network or HID I/O, so the scanner never writes to Freshservice by accident.
--api-key prompts for a key instead of using the stored one.

Per fob: read the keyboard-wedge output, switch to CCID with the feature
report and read the embedded Wiegand data with FF CA, decode the 26-bit
H10301 facility code + card number, then reboot the reader back into KBW.

The reader's stored config has KBW off (it powers up in CCID), and HID
documents no CCID -> KBW command. Its built-in web UI, reachable over the
reader's USB Ethernet (EEM) at 192.168.63.99, can: the scanner turns the
stored "Keyboard Wedge Enable" on and reboots the reader to get KBW, and
turns it back off on exit. The KBW -> CCID feature report also saves KBW
off, so it is turned on again before every reboot. The requests below are
the ones the web UI's webserver.js sends (read back from the reader, not
from HID docs).

FF CA returns the raw Wiegand bitstream LEFT-justified, so it must be
right-aligned before decoding. Verified against a real card: FF CA ->
CD A8 23 00 -> facility 155, card 20550, keyboard-wedge output 0336a08c
(the same 26 bits, right-aligned, in hex).

Needs root: hidraw + evdev grab, and the API key file. LOCK and KEY_FILE
are placeholders that smartcard-reader.nix fills in at eval time.
"""
import base64
import getpass
import json
import os
import select
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import evdev
import hid
from smartcard.System import readers
from smartcard.util import toHexString

VID, KBW_PID = 0x076B, 0x5428
READER_WEB = "http://192.168.63.99/"
DOMAIN = "lselectric.freshservice.com"  # same tenant as freshservice-mcp.nix
KEY_FILE = "@keyFile@"  # "" when freshservice-mcp has no key file: prompts
LOCK = "@lock@"
WORKSPACE_ID = 2  # IT
ASSET_TYPE_ID = 33001001822  # "Key Fob" (under Hardware)
PRODUCT_ID = 33000229548  # "HID ProxKey Fob"
HW = "_33000161308"  # suffix of the fields inherited from Hardware
# Key Fob custom fields, matched by label; add them in Freshservice Admin.
# Missing ones are skipped (the description always carries everything).
CUSTOM = ["Facility Code", "Fob Number", "Martin Number", "Wiegand Bits", "CHR Number"]


def decode(b):
    """FF CA bytes -> (bits, facility, card, martin, parity_ok) for 26-bit H10301.

    martin is the code Martin uses: the facility code's lowest bit on top of
    the 16-bit card number (an odd facility adds 65536), keeping only the
    last 5 digits, so 40784 + 65536 = 106320 is code 06320.
    """
    bits = format(int.from_bytes(b, "big") >> (len(b) * 8 - 26), "026b")
    even_ok = bits[0:13].count("1") % 2 == 0  # leading bit: even parity over bits 1-12
    odd_ok = bits[13:26].count("1") % 2 == 1  # trailing bit: odd parity over bits 13-24
    return bits, int(bits[1:9], 2), int(bits[9:25], 2), int(bits[8:25], 2) % 100000, even_ok and odd_ok


assert decode(bytes([0xCD, 0xA8, 0x23, 0x00]))[1:] == (155, 20550, 86086, True)
# Martin's examples: card 11713 (facility 155) is code 77249, 40784 is 06320.
assert decode(bytes([0x4D, 0x96, 0xE0, 0xC0]))[1:] == (155, 11713, 77249, True)
assert decode(bytes([0xCD, 0xCF, 0xA8, 0x40]))[1:] == (155, 40784, 6320, True)


def api(method, path, body=None):
    req = urllib.request.Request(
        "https://%s/api/v2/%s" % (DOMAIN, path), method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": AUTH, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def reader_web(endpoint, body):
    req = urllib.request.Request(READER_WEB + endpoint, data=body.encode(), headers={"Content-Type": "text/plain"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read().decode().strip()


def store_kbw(enabled):
    """Set the stored "Keyboard Wedge Enable" (config unit 04010100) and save it."""
    reply = reader_web("ajax", "0200000d0404010100010" + ("101" if enabled else "100"))
    if len(reply) == 6:  # the web UI treats a bare status reply as a failed write
        raise RuntimeError("reader rejected the Keyboard Wedge Enable write: %s" % reply)
    if reader_web("cjax", "ff6800010101") != "9000":  # MIB "Apply Changes"
        raise RuntimeError("reader did not save its config")


def kbw_present():
    d = kbw_input()
    if d:
        d.close()
    return bool(d)


def reboot_to_kbw():
    store_kbw(True)  # the feature-report switch to CCID saved KBW off
    try:
        reader_web("cjax", "ff6800010108")  # MIB "Reboot System"
    except OSError:
        pass  # the reader can drop the connection as it reboots
    # A KBW reader is still listed until the reboot takes it off the bus.
    wait_for(lambda: not kbw_present(), 10)
    return bool(wait_for(kbw_present, 30))


def wait_for(fn, seconds):
    end = time.time() + seconds
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.5)
    return None


def kbw_input():
    for p in evdev.list_devices():
        d = evdev.InputDevice(p)
        if d.info.vendor == VID and d.info.product == KBW_PID and evdev.ecodes.KEY_A in d.capabilities().get(evdev.ecodes.EV_KEY, []):
            return d
        d.close()
    return None


def read_kbw(dev):
    """Keystrokes typed for one fob, up to Enter or 1 s of silence."""
    dev.grab()  # keep the keystrokes out of whatever window has focus
    out, shift = "", False
    try:
        while True:
            if not select.select([dev], [], [], 1.0 if out else None)[0]:
                return out
            for e in dev.read():
                if e.type != evdev.ecodes.EV_KEY:
                    continue
                name = evdev.ecodes.KEY.get(e.code, "")
                name = name[0] if isinstance(name, list) else name
                if name in ("KEY_LEFTSHIFT", "KEY_RIGHTSHIFT"):
                    shift = e.value != 0
                elif e.value == 1 and name == "KEY_ENTER":
                    return out
                elif e.value == 1 and len(name) == 5:
                    # shortcut: letters and digits only (shifted digits read as digits), enough for hex/decimal KBW output; extend if the KBW format adds symbols
                    out += name[4] if shift else name[4].lower()
    finally:
        dev.close()


def connect(conn):
    try:
        conn.connect()
        return True
    except Exception:
        return False


def to_ccid():
    try:
        hid.Device(VID, KBW_PID).send_feature_report(bytes([0x00, 0xA5, 0x5A]))
    except hid.HIDException:
        pass  # re-enumeration mid-request is expected


def ccid_reader():
    r = [x for x in readers() if "OMNIKEY" in str(x).upper()]
    if not r and kbw_present():
        to_ccid()  # the reader sometimes ignores the switch; resend while it is still KBW
    return r


def read_ccid():
    """Switch KBW -> CCID and read the embedded data with FF CA."""
    to_ccid()
    r = wait_for(ccid_reader, 15)
    if not r:
        raise RuntimeError("reader did not come up in CCID mode")
    conn = r[0].createConnection()
    if not wait_for(lambda: connect(conn), 5):
        raise RuntimeError("no card in CCID mode; keep the fob on the reader until it is recorded")
    data, sw1, sw2 = conn.transmit([0xFF, 0xCA, 0x00, 0x00, 0x00])
    conn.disconnect()
    if (sw1, sw2) != (0x90, 0x00):
        raise RuntimeError("GET DATA failed: SW=%02X%02X" % (sw1, sw2))
    return bytes(data)


def show(raw, kbw):
    """Print the scan; the Freshservice field values, or None if it is not a 26-bit H10301 fob."""
    bits, facility, card, martin, parity_ok = decode(raw)
    # Martin expects the leading zeros.
    card5, translated = "%05d" % card, "%05d" % martin
    print("embedded (FF CA): %s" % toHexString(list(raw)))
    print("keyboard wedge  : %s" % (kbw or "(nothing typed)"))
    print("26-bit Wiegand  : %s %s %s %s  parity %s" % (bits[0], bits[1:9], bits[9:25], bits[25], "ok" if parity_ok else "BAD"))
    print("facility code   : %d" % facility)
    print("card number     : %s" % card5)
    print("martin number   : %s  (%s)" % (translated, "odd facility: +65536, last 5 digits" if facility % 2 else "even facility: same as card number"))
    if not parity_ok:
        print("Parity check failed: not a 26-bit H10301 fob.")
        return None
    return {"Facility Code": facility, "Fob Number": card5, "Martin Number": translated,
            "Wiegand Bits": bits, "CHR Number": kbw}


def find(serial):
    q = urllib.parse.quote("\"serial_number:'%s'\"" % serial)
    return api("GET", "assets?search=%s" % q).get("assets", [])


def ingest(raw, kbw):
    values = show(raw, kbw)
    serial = raw.hex().upper()
    if values is None:
        return
    if not kbw:
        print("The reader typed nothing in keyboard mode, and CHR Number is required, so nothing was recorded.")
        return
    if serial in seen:
        print("Already recorded this session.")
        return
    found = find(serial)
    if found:
        seen.add(serial)
        print("Already in Freshservice: asset #%s (%s)" % (found[0]["display_id"], found[0]["name"]))
        return
    facility, card5 = values["Facility Code"], values["Fob Number"]
    type_fields = {"product" + HW: PRODUCT_ID, "asset_state" + HW: "In Stock", "serial_number" + HW: serial}
    type_fields.update({fields[k]: values[k] for k in CUSTOM if k in fields})
    desc = "\n".join("%s: %s" % (k, values[k]) for k in CUSTOM) + "\nEmbedded data (FF CA): %s" % serial
    a = api("POST", "assets", {
        "name": "Fob %d-%s" % (facility, card5), "asset_tag": "FOB-%d-%s" % (facility, card5),
        "asset_type_id": ASSET_TYPE_ID, "workspace_id": WORKSPACE_ID,
        "description": desc, "type_fields": type_fields})["asset"]
    seen.add(serial)
    print("Recorded as asset #%s (%s)" % (a["display_id"], a["name"]))


def name_of(id_, *kinds):
    """Display name of a linked record, trying each kind (a user can be a requester or an agent)."""
    if not id_:
        return "(none)"
    for kind in kinds:
        try:
            r = api("GET", "%ss/%d" % (kind, id_))[kind]
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            raise
        return r.get("name") or ("%s %s" % (r.get("first_name") or "", r.get("last_name") or "")).strip()
    return "#%d" % id_


def lookup(raw, kbw):
    values = show(raw, kbw)
    found = find(raw.hex().upper())
    if not found:
        print("\nNot in Freshservice.")
        return
    a = api("GET", "assets/%d?include=type_fields" % found[0]["display_id"])["asset"]
    tf = a.get("type_fields") or {}
    print("\nFreshservice asset #%s: %s  (tag %s)" % (a["display_id"], a["name"], a["asset_tag"]))
    for label, value in [
            ("state", tf.get("asset_state" + HW)),
            ("used by", name_of(a.get("user_id"), "requester", "agent")),
            ("department", name_of(a.get("department_id"), "department")),
            ("location", name_of(a.get("location_id"), "location")),
            ("assigned on", a.get("assigned_on") or "(none)"),
            ("serial", tf.get("serial_number" + HW))]:
        print("  %-15s: %s" % (label, value))
    for k in CUSTOM:
        stored = tf.get(fields[k]) if k in fields else None
        differs = values is not None and str(stored) != str(values[k])
        print("  %-15s: %s%s" % (k.lower(), stored, "   <-- scan reads %s" % values[k] if differs else ""))


MODE = sys.argv[1] if len(sys.argv) > 1 else None
if MODE not in ("ingest", "lookup"):
    sys.exit("usage: sudo omnikey-fob ingest|lookup [--api-key]")
if os.geteuid() != 0:
    sys.exit("Run with sudo: the scanner needs the reader's raw HID devices and the Freshservice API key.")
# --api-key prompts for a key instead of using the stored one (and so does a
# missing key file); prompted, so the key stays out of shell history and ps.
if "--api-key" in sys.argv[2:] or not os.path.exists(KEY_FILE):
    key = getpass.getpass("Freshservice API key: ")
else:
    key = open(KEY_FILE).read()
AUTH = "Basic " + base64.b64encode(key.strip().encode() + b":X").decode()
seen, fields = set(), {}
try:
    groups = api("GET", "asset_types/%d/fields" % ASSET_TYPE_ID)["asset_type_fields"]
except urllib.error.HTTPError as e:
    sys.exit("Freshservice rejected the API key (HTTP %s)." % e.code if e.code in (401, 403) else "Freshservice error %s: %s" % (e.code, e.read().decode(errors="replace")))
for group in groups:
    if group["field_header"] == "Key Fob":
        fields = {f["label"]: f["name"] for f in group["fields"]}
missing = [k for k in CUSTOM if k not in fields]
if missing:
    print("Key Fob fields missing in Freshservice (description only): %s" % ", ".join(missing), file=sys.stderr)

try:
    store_kbw(True)
except OSError as e:
    sys.exit("Cannot reach the reader's web interface at %s (is it plugged in?): %s" % (READER_WEB, e))
open(LOCK, "w").close()
last_kbw = None
try:
    if not kbw_present() and not reboot_to_kbw():
        sys.exit("Reader did not come up in keyboard mode after a reboot.")
    while True:
        dev = kbw_input()
        if not dev:
            print("Waiting for the reader (keyboard mode)...", file=sys.stderr)
            dev = wait_for(kbw_input, 3600)
            if not dev:
                continue
        print("\nPresent a fob and leave it on the reader until it is %s (Ctrl+C to stop)." % ("recorded" if MODE == "ingest" else "shown"))
        try:
            kbw = read_kbw(dev)
            if kbw and kbw == last_kbw:
                # The fob still on the reader re-typed after the reset; skip the mode switch.
                print("Same fob as last time: remove it and present the next one.")
                continue
            (ingest if MODE == "ingest" else lookup)(read_ccid(), kbw)
            last_kbw = kbw  # only after a full read, so a failed scan can be retried
        except urllib.error.HTTPError as e:
            print("Freshservice error %s: %s" % (e.code, e.read().decode(errors="replace")), file=sys.stderr)
        except Exception as e:  # pcsc/hid/usb hiccups: report and keep scanning
            print("Scan failed, try that fob again: %s" % e, file=sys.stderr)
        if not reboot_to_kbw():
            sys.exit("Reader did not return to keyboard mode after a reboot: unplug it and plug it back in, then rerun.")
        print("Remove the fob.")
except KeyboardInterrupt:
    pass
finally:
    # Leave the reader as found: KBW off in its stored config, CCID now.
    # A second Ctrl+C here would skip the lock removal and leave the udev CCID switch disabled.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    print("Restoring the reader to CCID mode (this can take a few seconds)...", file=sys.stderr)
    try:
        try:
            store_kbw(False)
        except (OSError, RuntimeError) as e:
            print("Could not turn keyboard mode back off; the udev rule will switch it to CCID on next plug-in: %s" % e, file=sys.stderr)
        if kbw_present():
            to_ccid()
    finally:
        os.remove(LOCK)
