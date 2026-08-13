# dream — AMD desktop (eiros hostname DREAM).
{ pkgs, ... }:
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

  # Nothing on usb1-port8 has ever enumerated, but something there keeps
  # half-answering, so every boot the kernel grinds through its retry cycle:
  # `device descriptor read/64, error -110` → `Device not responding to setup
  # address` → `attempt power cycle` → `unable to enumerate USB device`. That
  # port sits on the SAME xHCI controller (0000:0d:00.0) as the onboard USB
  # audio device on 1-7, which carries every real sink and source on this box —
  # Speakers, Front Headphones, S/PDIF, and the Line Input mic.
  #
  # The audio card registers ~1 s after port 8 goes quiet, measured across three
  # boots, so those devices are missing for most of a minute after login. The
  # probe itself is not the cost: re-authorizing 1-7 while port 8 is idle brings
  # the card back in 4 s with no errors at all.
  #
  # `early_stop` was tried first and is too weak. Per the kernel ABI docs it
  # "limits each port to just two initialization attempts" — a cap, not an off
  # switch. It cut the cycle 64 s → 43 s and the outage shrank in lockstep,
  # which is what confirmed the causal link, but 43 s is still 43 s. `disable`
  # is the actual off switch: devices on the port "will not be detected,
  # initialized, or enumerated".
  #
  # Both are set. `disable` does the work; `early_stop` stays as a fallback that
  # still caps the damage at two attempts if a hub ever ignores `disable`.
  #
  # This turns port 8 OFF. Justified because nothing has ever enumerated there
  # across every boot on record, and it is one config line to revert. Note the
  # board's ACPI port data is NOT the justification and cannot be trusted: port
  # 7, which carries the audio device, is also reported
  # `connect_type = "not used"`.
  #
  # Has to be a systemd unit, NOT a udev rule: USB port devices have an empty
  # `uevent` and no subsystem, and udev's database holds zero `usb_port` entries,
  # so there is nothing for a rule to match. The path is anchored on the
  # controller's stable PCI address and globs the USB bus number, which is not.
  #
  # The real fix is physical — find whatever is on that port and unplug it.
  systemd.services.usb-port8-disable = {
    description = "Disable usb1-port8, which never enumerates and stalls USB audio";
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-modules-load.service" ];
    path = [ pkgs.coreutils ]; # seq/sleep, not in a unit's default PATH
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Polls because the port only exists once xhci_hcd has bound and
      # registered the root hub, which races this unit. It has to win that race:
      # `disable` only helps if it lands before the port starts enumerating (on
      # the last boot the unit wrote at +8 s and port 8 connected at +13 s).
      # Exits 0 either way — a missing port must never fail the boot.
      ExecStart = pkgs.writeShellScript "usb-port8-disable" ''
        set -u
        for _ in $(seq 1 250); do
          for d in /sys/bus/pci/devices/0000:0d:00.0/usb*/*-0:1.0/usb*-port8; do
            if [ -w "$d/disable" ]; then
              # Fallback first, so the cap is in place even if `disable` is a
              # no-op on this hub.
              [ -w "$d/early_stop" ] && echo 1 > "$d/early_stop"
              echo 1 > "$d/disable"
              echo "disabled $d (early_stop=$(cat "$d/early_stop" 2>/dev/null))"
              exit 0
            fi
          done
          sleep 0.1
        done
        echo "usb1-port8 never appeared; nothing to do" >&2
        exit 0
      '';
    };
  };
}
