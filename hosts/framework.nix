# framework — Framework 16 work laptop (eiros hostname LS-04380).
{ itera, ... }:
{
  # Framework 16 (AMD Ryzen 7040) hardware quirks, re-exported by itera from
  # nixos-hardware. Board selection is an import-time choice the module system
  # can't toggle from config, so it goes in `imports` rather than `itera.*`.
  imports = [ itera.hardwareModules.framework-16-7040-amd ];

  itera = {
    networking.hostName = "LS-04380";
    hardware.cpu = "amd";

    # Deliberately-invalid placeholder so the config still evaluates (satisfies
    # itera.disko's non-empty-device assertion) WITHOUT hardcoding a real disk.
    # `disko-install --disk main /dev/<real>` overrides this at install time, so
    # you never edit this file to install — and a forgotten `--disk` fails safe
    # (disko errors on the bogus path instead of wiping a real disk).
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "32G"; # >= RAM for hibernation

    fingerprint.enable = true; # on by default; explicit for clarity
    printing.enable = true; # itera default: hplipWithPlugin + mDNS + GUI (matches eiros work)

    # Colemak-DH across console + mango session + greeter (eiros keyboard_layout.nix).
    keyboard.layout = "us";
    keyboard.variant = "colemak_dh";

    # Three-monitor layout (translated from eiros.hardware.framework monitors.nix).
    programs.mango.monitors = {
      "eDP-1" = {
        width = 2560;
        height = 1600;
        refresh = 165;
        x = 0;
        y = 0;
      };
      "DP-10" = {
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 2560;
        y = 0;
      };
      "DP-11" = {
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 4480;
        y = 0;
      };
    };
    # nvidia stays OFF (itera.nvidia is opt-in / default false) — matches eiros.
  };
  # SKIPPED (per user): MT7922 Bluetooth softdep/autosuspend quirks; 3-finger
  # gesturebinds and trackpad flags can be added later if wanted (not essentials).
}
