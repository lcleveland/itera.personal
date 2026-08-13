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

    # Force-load snd_usb_audio in stage 2 so it is resident BEFORE the onboard
    # ASUS USB audio device (0b05:1b7c on usb 1-7) enumerates. That device
    # carries every real sink and source on this box — Speakers, Front
    # Headphones, S/PDIF, and the Line Input mic — so until its card registers
    # there is no audio and no microphone at all.
    #
    # Without this it is a race, and losing it costs ~50 s. Compare boots on the
    # same kernel (7.1.8):
    #   • module loaded BEFORE the device appears → card up ~1 s later, clean.
    #   • device appears BEFORE the module (udev autoloads it ~17 s in) → the
    #     probe then burns ~50 s in `parse_audio_format_rates_v2v3(): unable to
    #     retrieve number of sample rates` / `cannot get freq (v2/v3): err -110`
    #     (ETIMEDOUT) before `snd-usb-audio` finally registers.
    # On a lost race the card lands ~66 s after boot but the session starts at
    # ~31 s, which is the "no audio devices or mic for a while after logging in"
    # window. stage-2 systemd-modules-load runs ~1 s before usb 1-7 is detected,
    # so listing the module here wins the race deterministically.
    #
    # NOTE: this is a workaround, not the root cause. A device on usb1-port8
    # fails enumeration on every boot (`device descriptor read/64, error -110`
    # → `unable to enumerate USB device`) and its retry storm overlaps the audio
    # probe on the same root hub. Physically removing whatever is on port 8
    # (controller 0000:0d:00.0, same hub as the audio device) is the real fix.
    hardware.kernelModules = [ "snd_usb_audio" ];

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
