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

  # Read an HID Prox (125 kHz) credential over PC/SC and decode the 26-bit
  # H10301 Wiegand value into facility code + card number. FF CA returns the
  # raw Wiegand bitstream LEFT-justified, so it must be right-aligned before
  # decoding. Verified against a real card: FF CA -> CD A8 23 00 -> facility
  # 155, card 20550 (matches the keyboard-wedge value 0x0336A08D).
  omnikey-read-prox = pkgs.writers.writePython3Bin "omnikey-read-prox"
    {
      libraries = [ pkgs.python3Packages.pyscard ];
      flakeIgnore = [ "E501" ];
    } ''
    import sys
    import time
    from smartcard.System import readers
    from smartcard.util import toHexString

    rs = readers()
    if not rs:
        print("No PC/SC reader found. Is the reader in CCID mode and pcscd running?", file=sys.stderr)
        sys.exit(1)

    omnikey = [r for r in rs if "OMNIKEY" in str(r).upper()]
    target = omnikey[0] if omnikey else rs[0]
    print("Using reader: %s" % target, file=sys.stderr)

    conn = target.createConnection()
    connected = False
    print("Present a card...", file=sys.stderr)
    for _ in range(40):
        try:
            conn.connect()
            connected = True
            break
        except Exception:
            time.sleep(0.5)
    if not connected:
        print("No card detected.", file=sys.stderr)
        sys.exit(1)

    # PC/SC GET DATA pseudo-APDU: return the card's data (Wiegand bits for Prox).
    data, sw1, sw2 = conn.transmit([0xFF, 0xCA, 0x00, 0x00, 0x00])
    if (sw1, sw2) != (0x90, 0x00):
        print("GET DATA failed: SW=%02X%02X (raw=%s)" % (sw1, sw2, toHexString(data)), file=sys.stderr)
        sys.exit(1)

    b = bytes(data)
    raw = int.from_bytes(b, "big")
    # The reader returns the raw Wiegand bitstream left-justified, so right-
    # align the 26-bit field. 26-bit H10301 layout (after alignment):
    # 1 leading parity + 8-bit facility + 16-bit card number + 1 trailing parity.
    wiegand = raw >> (len(b) * 8 - 26)
    bits = format(wiegand, "026b")
    lead_parity, facility_bits, card_bits, trail_parity = (
        bits[0], bits[1:9], bits[9:25], bits[25],
    )
    facility = int(facility_bits, 2)
    card = int(card_bits, 2)

    print("raw bytes      : %s" % toHexString(data))
    print("26-bit Wiegand : %s %s %s %s" % (lead_parity, facility_bits, card_bits, trail_parity))
    print("                 P FFFFFFFF CCCCCCCCCCCCCCCC P   (P=parity F=facility C=card)")
    print("leading parity : %s" % lead_parity)
    print("facility code  : %sb = 0x%02X = %d" % (facility_bits, facility, facility))
    print("card number    : %sb = 0x%04X = %d" % (card_bits, card, card))
    print("trailing parity: %s" % trail_parity)

    # Some systems fold the facility-code parity into the card number: an odd
    # facility code adds 65536 (the 17th bit) to the card number.
    translated = card + (65536 if facility % 2 else 0)
    note = "  (card + 65536, facility is odd)" if facility % 2 else ""
    print("translated     : %d%s" % (translated, note))
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
      omnikey-read-prox # read + decode HID Prox facility code / card number
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
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${omnikey-ccid-switch}/bin/omnikey-ccid-switch";
      };
    };
  };
}
