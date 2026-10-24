{
  config,
  pkgs,
  ...
}:
let
  # Switch an OMNIKEY 5x27CK from Keyboard Wedge to CCID mode.
  # Per HID docs this is a HID Set Feature Report (report id 0x00, bytes
  # 0xA5 0x5A) to the KBW-mode device (076b:5428). It then re-enumerates as
  # the CCID composite device 076b:5427, which the bundled ccid driver
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
        # The device re-enumerates as 076b:5427; an I/O error here is expected.
        pass
  '';

  # While a fob scanner runs it holds this file so the udev auto-switch below
  # leaves the reader in KBW mode; the scanner switches it itself.
  inventoryLock = "/run/omnikey-inventory";

  # Fob scanner, `sudo omnikey-fob ingest|lookup`; see omnikey-fob.py's docstring.
  # The key path follows freshservice-mcp's (toString null = "", which the
  # script treats as missing and prompts for).
  omnikey-fob = pkgs.writers.writePython3Bin "omnikey-fob"
    {
      libraries = with pkgs.python3Packages; [ pyscard hid evdev ];
      flakeIgnore = [ "E501" ];
    }
    (
      builtins.replaceStrings
        [ "@lock@" "@keyFile@" ]
        [ inventoryLock (toString config.services.freshservice-mcp.apiKeyFile) ]
        (builtins.readFile ./omnikey-fob.py)
    );
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
      omnikey-fob # `ingest` records fobs in Freshservice, `lookup` shows them (run with sudo)
    ];

    # keyd grabs every keyboard (hosts/common.nix) and would retype the fob
    # numbers into the focused window; the scanner needs the reader to itself.
    services.keyd.keyboards.default.ids = [ "-076b:5428" ];

    # Auto-switch the reader to CCID mode whenever it appears in KBW mode
    # (product id 5428). Once switched it enumerates as 5427 and no longer
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
