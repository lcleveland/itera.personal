# dream — AMD desktop (eiros hostname DREAM).
{ ... }:
{
  # Dream-only apps, migrated from the old eiros.users.personal repo.
  imports = [
    ./apps/dream/awakened-poe-trade.nix
    ./apps/dream/exiled-exchange-2.nix
    ./apps/dream/stability-matrix.nix
    ./apps/dream/orca-slicer.nix
    ./apps/dream/pob.nix
    ./apps/dream/python.nix
    ./apps/dream/vesktop.nix
  ];

  itera = {
    networking.hostName = "DREAM";
    hardware.cpu = "amd";

    # This host is nixosConfigurations.dream; the hostname (DREAM) differs from
    # the flake attribute, so set it explicitly (else `itera update`/`rebuild`
    # would pass `--hostname DREAM` and miss `#dream`).
    update.configuration = "dream";

    # Deliberately-invalid placeholder so the config still evaluates (satisfies
    # itera.disko's non-empty-device assertion) WITHOUT hardcoding a real disk.
    # `disko-install --disk main /dev/<real>` overrides this at install time, so
    # you never edit this file to install — and a forgotten `--disk` fails safe
    # (disko errors on the bogus path instead of wiping a real disk).
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "32G"; # >= RAM enables `systemctl hibernate`

    # Dual-monitor layout (translated from eiros.hardware.dream monitors.nix).
    programs.mango.monitors = {
      "DP-4" = {
        width = 1920;
        height = 1200;
        refresh = 60;
        x = 0;
        y = 0;
      };
      "DP-3" = {
        width = 3840;
        height = 1080;
        refresh = 120;
        x = 0;
        y = 1200;
      };
    };

    # Gaming (opt-in): Steam + Proton-GE + gamescope + gamemode.
    gaming.enable = true;

    # Local AI (opt-in): ollama runtime + open-webui chat UI.
    ai.ollama.enable = true;
    ai.openWebui.enable = true;
    # acceleration defaults to "auto" -> CUDA build when itera.nvidia is on, else
    # CPU. If dream has an NVIDIA GPU, also set `itera.nvidia.enable = true;` (auto
    # then picks the CUDA build); for an AMD GPU set `ai.ollama.acceleration = "rocm";`.
  };
  # SKIPPED (per user): MT7927 initrd systemd-udevd TimeoutStopSec BT boot-hang hack.
}
