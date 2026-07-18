# dream — AMD desktop (eiros hostname DREAM).
{ ... }:
{
  itera = {
    networking.hostName = "DREAM";
    hardware.cpu = "amd";

    # disko WIPES this disk. Verify the device on the machine (`lsblk`) before install.
    disko.device = "/dev/nvme0n1"; # CHANGE-ME if different
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
