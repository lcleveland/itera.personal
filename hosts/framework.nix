# framework — Framework 16 work laptop (eiros hostname LS-04380).
{ itera, lib, ... }:
{
  # Framework 16 (AMD Ryzen 7040) hardware quirks, re-exported by itera from
  # nixos-hardware. Board selection is an import-time choice the module system
  # can't toggle from config, so it goes in `imports` rather than `itera.*`.
  imports = [
    itera.hardwareModules.framework-16-7040-amd
    # Work-tenant role: Netskope, Falcon, the work-network MCP servers, FDE +
    # TPM2 and printing, shared with x1yoga. Its apps live under apps/work/ (not
    # apps/framework/) because none of them is specific to this laptop model.
    ./work.nix
  ];

  # Panel goes DIM at 97-100% brightness (correct below that). Since 6.14 amdgpu
  # applies a "custom brightness curve" derived from the panel's EDID luminance
  # data, and it is broken at the top of the range on BOE panels behind an AMD
  # iGPU — which is what the Framework 16 ships. scale_input_to_fw() omits the
  # `- min` term its own comment implies, so full brightness scales to 268 and
  # overshoots AMDGPU_MAX_BL_LEVEL (0xFF); the scale_fw_to_input() round-trip
  # then exceeds 65535 and wraps backlight_pwm_u16_16 to a near-minimum duty.
  #
  # 0x40000 = DC_DISABLE_CUSTOM_BRIGHTNESS_CURVE, OR'd with the 0x10
  # (DC_DISABLE_PSR) that nixos-hardware's framework/16-inch/common/amd.nix
  # already sets. Add 0x400 (DC_DISABLE_REPLAY) -> 0x40410 if flicker appears.
  #
  # mkAfter, not mkForce: nixos-hardware sets its 0x10 as a plain list element
  # rather than mkDefault, and kernelParams is a list that concatenates, so
  # priority cannot override it. Both land on the cmdline and the LAST
  # assignment wins for module params — mkAfter is what guarantees ours is last.
  # Verify after rebooting: /sys/module/amdgpu/parameters/dcdebugmask == 262160.
  boot.kernelParams = lib.mkAfter [ "amdgpu.dcdebugmask=0x40010" ];

  itera = {
    networking.hostName = "LS-04380";
    hardware.cpu = "amd";

    # This host is nixosConfigurations.framework; the hostname (LS-04380) differs
    # from the flake attribute, so set it explicitly (else `itera update`/`rebuild`
    # would pass `--hostname LS-04380` and miss `#framework`).
    update.configuration = "framework";

    # Deliberately-invalid placeholder so the config still evaluates (satisfies
    # itera.disko's non-empty-device assertion) WITHOUT hardcoding a real disk.
    # `disko-install --disk main /dev/<real>` overrides this at install time, so
    # you never edit this file to install — and a forgotten `--disk` fails safe
    # (disko errors on the bogus path instead of wiping a real disk).
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "32G"; # >= RAM for hibernation

    # Set explicit, because the keyboard is USB-internal; itera already defaults it on
    # when encryption is enabled (work.nix). Without USB HID in the initrd, the
    # recovery-passphrase fallback (when the TPM refuses to unseal) would have no
    # keyboard and lock us out.
    hardware.initrd.usbSupport = true;

    fingerprint.enable = true; # on by default; explicit for clarity

    # Colemak-DH across console + mango session + greeter (eiros keyboard_layout.nix).
    keyboard.layout = "us";
    keyboard.variant = "colemak_dh";

    # Monitor layout (origin top-left, +x right / +y down):
    #   eDP-1 laptop on the left, bottom-aligned with the ultrawide.
    #   ultrawide: 49" super-ultrawide (5120x1440 @165) to the right of the laptop.
    #   lenovo: Lenovo T24i-10 (upside down) flush above the ultrawide's top-left
    #     corner (edges meet at y=1080, no overlap).
    # The dock is DP-MST, so its connectors get a new number on every replug
    # (DP-10/11, then DP-12/13, ...): match those by model + serial, not name.
    programs.mango.monitors = {
      "eDP-1" = {
        width = 2560;
        height = 1600;
        refresh = 165;
        x = 0;
        y = 920; # bottom-aligned with the ultrawide (1080 + 1440 - 1600)
      };
      lenovo = {
        name = "^DP-[0-9]+$";
        model = "LEN T24i-10";
        serial = "VNA4B1P6";
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 2560; # left-aligned with the ultrawide
        y = 0; # sits directly above the ultrawide (bottom edge at y=1080)
        transform = "180"; # panel physically mounted upside down
      };
      ultrawide = {
        name = "^DP-[0-9]+$";
        model = "XG49DH16C";
        serial = "000000000001";
        width = 5120;
        height = 1440;
        refresh = 165;
        x = 2560; # right of the laptop
        y = 1080; # below the lenovo
      };
    };

    # Pointer input. trackpad_natural_scrolling is not a curated itera option, so
    # it goes through the per-user `extraConfig` escape hatch, which the hjem
    # renderer appends verbatim to ~/.config/mango/config.conf (last section in

    # the file).
    #
    #   mango defaults it to 0 (content moves opposite the fingers). 1 = natural
    #   ("content follows the gesture", the macOS-style direction). The external
    #   mouse wheel keeps the default direction.
    users.lcleveland.programs.mango.extraConfig = ''
      trackpad_natural_scrolling=1
    '';
    # nvidia stays OFF (itera.nvidia is opt-in / default false) — matches eiros.
  };
  # SKIPPED (per user): MT7922 Bluetooth softdep/autosuspend quirks; 3-finger
  # gesturebinds and trackpad flags can be added later if wanted (not essentials).
}
