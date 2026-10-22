{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Switch an OMNIKEY 5x27CK from Keyboard Wedge to CCID mode.
  # Per HID docs this is a HID Set Feature Report (report id 0x00, bytes
  # 0xA5 0x5A) to the KBW-mode device (076b:5428). It then re-enumerates as
  # the CCID composite device 076b:5A27, which the bundled ccid driver
  # already supports. hid uses hidraw, so no kernel-driver detach is needed.
  # NOTE: nixpkgs python3Packages.hid exposes the hid.Device / hid.HIDException
  # API (not the lowercase hid.device() API of the cython hidapi package).
  omnikey-ccid-switch = pkgs.writers.writePython3Bin "omnikey-ccid-switch"
    {
      libraries = [ pkgs.python3Packages.hid ];
      flakeIgnore = [ "E501" ];
    } ''
    import sys
    import hid

    try:
        d = hid.Device(0x076b, 0x5428)  # KBW-mode product id
    except hid.HIDException:
        # Not in KBW mode (already CCID, or not present) -> nothing to do.
        sys.exit(0)

    try:
        d.send_feature_report(bytes([0x00, 0xA5, 0x5A]))  # KBW -> CCID
    except hid.HIDException:
        # The device re-enumerates as 076b:5A27; an I/O error here is expected.
        pass
  '';

  # While omnikey-read-prox runs it holds this file so the udev auto-switch
  # below leaves the reader in KBW mode; the scanner switches it itself.
  inventoryLock = "/run/omnikey-inventory";

  # Fob inventory scanner: loops over fobs and records each one in Freshservice
  # as a "Key Fob" hardware asset (serial number = the embedded PC/SC data).
  # Per fob: read the keyboard-wedge output (the reader powers up in KBW mode),
  # switch to CCID and read the embedded Wiegand data with FF CA, decode the
  # 26-bit H10301 facility code + card number, then USB-reset the reader so it
  # comes back in KBW mode for the next fob. HID documents no CCID -> KBW
  # command, so the reset is how we get back (the feature-report switch does
  # not survive re-enumeration).
  #
  # FF CA returns the raw Wiegand bitstream LEFT-justified, so it must be
  # right-aligned before decoding. Verified against a real card: FF CA ->
  # CD A8 23 00 -> facility 155, card 20550. That card's keyboard-wedge output
  # was 0336A08D, which carries the same facility/card but a different final
  # bit, so both are recorded rather than one derived from the other.
  #
  # Needs root: hidraw + evdev grab + USB reset, and the API key file.
  omnikey-read-prox = pkgs.writers.writePython3Bin "omnikey-read-prox"
    {
      libraries = with pkgs.python3Packages; [ pyscard hid evdev ];
      flakeIgnore = [ "E501" ];
    } ''
    import base64
    import fcntl
    import glob
    import json
    import os
    import select
    import sys
    import time
    import urllib.error
    import urllib.parse
    import urllib.request

    import evdev
    import hid
    from smartcard.System import readers
    from smartcard.util import toHexString

    VID, KBW_PID, CCID_PID = 0x076B, 0x5428, 0x5A27
    DOMAIN = "lselectric.freshservice.com"
    KEY_FILE = "/persist/secrets/freshservice-api-key"
    LOCK = "${inventoryLock}"
    WORKSPACE_ID = 2  # IT
    ASSET_TYPE_ID = 33001001822  # "Key Fob" (under Hardware)
    PRODUCT_ID = 33000229548  # "HID ProxKey Fob"
    HW = "_33000161308"  # suffix of the fields inherited from Hardware
    # Key Fob custom fields, matched by label; add them in Freshservice Admin.
    # Missing ones are skipped (the description always carries everything).
    CUSTOM = ["Facility Code", "Card Number", "Translated Number", "Wiegand Bits", "Keyboard Wedge Output"]
    USBDEVFS_RESET = 0x5514


    def decode(b):
        """FF CA bytes -> (bits, facility, card, parity_ok) for 26-bit H10301."""
        bits = format(int.from_bytes(b, "big") >> (len(b) * 8 - 26), "026b")
        even_ok = bits[0:13].count("1") % 2 == 0  # leading bit: even parity over bits 1-12
        odd_ok = bits[13:26].count("1") % 2 == 1  # trailing bit: odd parity over bits 13-24
        return bits, int(bits[1:9], 2), int(bits[9:25], 2), even_ok and odd_ok


    assert decode(bytes([0xCD, 0xA8, 0x23, 0x00]))[1:] == (155, 20550, True)


    def api(method, path, body=None):
        req = urllib.request.Request(
            "https://%s/api/v2/%s" % (DOMAIN, path), method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": AUTH, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)


    def usb_devices(pid):
        """sysfs dirs of the reader with this product id."""
        out = []
        for f in glob.glob("/sys/bus/usb/devices/*/idVendor"):
            d = os.path.dirname(f)
            if open(f).read().strip() == "%04x" % VID and open(d + "/idProduct").read().strip().lower() == "%04x" % pid:
                out.append(d)
        return out


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


    def back_to_kbw():
        """USB-reset the CCID-mode reader so it re-enumerates in KBW mode."""
        for d in usb_devices(CCID_PID):
            bus, dev = (int(open(d + "/" + n).read()) for n in ("busnum", "devnum"))
            with open("/dev/bus/usb/%03d/%03d" % (bus, dev), "wb") as f:
                fcntl.ioctl(f, USBDEVFS_RESET, 0)
        if wait_for(kbw_input, 10):
            return True
        # Reset alone may not reboot the reader: power-cycle its port instead.
        for d in usb_devices(CCID_PID):
            port = d + "/port/disable"
            if os.path.exists(port):
                open(port, "w").write("1")
                time.sleep(1)
                open(port, "w").write("0")
        return bool(wait_for(kbw_input, 10))


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


    def read_ccid():
        """Switch KBW -> CCID and read the embedded data with FF CA."""
        try:
            hid.Device(VID, KBW_PID).send_feature_report(bytes([0x00, 0xA5, 0x5A]))
        except hid.HIDException:
            pass  # re-enumeration mid-request is expected
        r = wait_for(lambda: [x for x in readers() if "OMNIKEY" in str(x).upper()], 15)
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


    def record(raw, kbw, seen, fields):
        bits, facility, card, parity_ok = decode(raw)
        serial = raw.hex().upper()
        # Some systems fold the facility-code parity into the card number: an odd
        # facility code adds 65536 (the 17th bit) to the card number.
        translated = card + (65536 if facility % 2 else 0)
        print("embedded (FF CA): %s" % toHexString(list(raw)))
        print("keyboard wedge  : %s" % (kbw or "(nothing typed)"))
        print("26-bit Wiegand  : %s %s %s %s  parity %s" % (bits[0], bits[1:9], bits[9:25], bits[25], "ok" if parity_ok else "BAD"))
        print("facility code   : %d" % facility)
        print("card number     : %d  (translated %d)" % (card, translated))
        if not parity_ok:
            print("Parity check failed: not a 26-bit H10301 fob, so nothing was recorded.")
            return
        if serial in seen:
            print("Already recorded this session.")
            return
        q = urllib.parse.quote("\"serial_number:'%s'\"" % serial)
        found = api("GET", "assets?search=%s" % q).get("assets", [])
        if found:
            seen.add(serial)
            print("Already in Freshservice: asset #%s (%s)" % (found[0]["display_id"], found[0]["name"]))
            return
        values = {"Facility Code": facility, "Card Number": card, "Translated Number": translated,
                  "Wiegand Bits": bits, "Keyboard Wedge Output": kbw}
        type_fields = {"product" + HW: PRODUCT_ID, "asset_state" + HW: "In Stock", "serial_number" + HW: serial}
        type_fields.update({fields[k]: values[k] for k in CUSTOM if k in fields})
        desc = "\n".join("%s: %s" % (k, values[k]) for k in CUSTOM) + "\nEmbedded data (FF CA): %s" % serial
        a = api("POST", "assets", {
            "name": "Fob %d-%d" % (facility, card), "asset_tag": "FOB-%d-%d" % (facility, card),
            "asset_type_id": ASSET_TYPE_ID, "workspace_id": WORKSPACE_ID,
            "description": desc, "type_fields": type_fields})["asset"]
        seen.add(serial)
        print("Recorded as asset #%s (%s)" % (a["display_id"], a["name"]))


    if os.geteuid() != 0:
        sys.exit("Run with sudo: the scanner needs the reader's raw HID/USB devices and the Freshservice API key.")
    AUTH = "Basic " + base64.b64encode(open(KEY_FILE).read().strip().encode() + b":X").decode()
    fields = {}
    for group in api("GET", "asset_types/%d/fields" % ASSET_TYPE_ID)["asset_type_fields"]:
        if group["field_header"] == "Key Fob":
            fields = {f["label"]: f["name"] for f in group["fields"]}
    missing = [k for k in CUSTOM if k not in fields]
    if missing:
        print("Key Fob fields missing in Freshservice (description only): %s" % ", ".join(missing), file=sys.stderr)

    open(LOCK, "w").close()
    seen, last_kbw = set(), None
    try:
        if usb_devices(CCID_PID) and not back_to_kbw():
            sys.exit("Reader is stuck in CCID mode: unplug it and plug it back in.")
        while True:
            dev = kbw_input()
            if not dev:
                print("Waiting for the reader (keyboard mode)...", file=sys.stderr)
                dev = wait_for(kbw_input, 3600)
                if not dev:
                    continue
            print("\nPresent a fob and leave it on the reader until it is recorded (Ctrl+C to stop).")
            try:
                kbw = read_kbw(dev)
                if kbw and kbw == last_kbw:
                    # The fob still on the reader re-typed after the reset; skip the mode switch.
                    print("Same fob as last time: remove it and present the next one.")
                    continue
                record(read_ccid(), kbw, seen, fields)
                last_kbw = kbw  # only after a full read, so a failed scan can be retried
            except urllib.error.HTTPError as e:
                print("Freshservice error %s: %s" % (e.code, e.read().decode(errors="replace")), file=sys.stderr)
            except Exception as e:  # pcsc/hid/usb hiccups: report and keep scanning
                print("Scan failed, try that fob again: %s" % e, file=sys.stderr)
            if not back_to_kbw():
                sys.exit("Reader did not return to keyboard mode: unplug it and plug it back in, then rerun.")
            print("Remove the fob.")
    except KeyboardInterrupt:
        pass
    finally:
        os.remove(LOCK)
  '';
in
{
  config = {
    # PC/SC daemon. The NixOS pcscd module loads pkgs.ccid as a plugin by
    # default, which is the driver the OMNIKEY 5427 G2 uses in CCID mode.
    services.pcscd.enable = true;

    environment.systemPackages = [
      pkgs.pcsc-tools # pcsc_scan: detect the reader and read card UIDs
      pkgs.opensc # opensc-tool / PKCS#11 middleware (general smartcard use)
      omnikey-ccid-switch # manual KBW -> CCID switch
      omnikey-read-prox # fob inventory scanner -> Freshservice (run with sudo)
    ];

    # Auto-switch the reader to CCID mode whenever it appears in KBW mode
    # (product id 5428). Once switched it enumerates as 5A27 and no longer
    # matches this rule, so the switch is self-limiting/idempotent. Run the USB
    # I/O from a oneshot service rather than directly in RUN+= to avoid udev
    # timeouts.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="076b", ATTR{idProduct}=="5428", TAG+="systemd", ENV{SYSTEMD_WANTS}+="omnikey-ccid-switch.service"
    '';

    systemd.services.omnikey-ccid-switch = {
      description = "Switch OMNIKEY 5427 from Keyboard Wedge to CCID mode";
      # The inventory scanner needs KBW mode and drives the switch itself.
      unitConfig.ConditionPathExists = "!${inventoryLock}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${omnikey-ccid-switch}/bin/omnikey-ccid-switch";
      };
    };
  };
}
