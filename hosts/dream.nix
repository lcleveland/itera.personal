# dream — AMD desktop (eiros hostname DREAM).
{
  pkgs,
  ...
}:
let
  # The onboard MT7927 (MT6639 "Filogic 380") is ONE M.2 module exposing two
  # functions: WiFi as PCIe (14c3:7927 at 0000:09:00.0) and Bluetooth as USB,
  # and the USB half is what sits on usb1-port8.
  #
  # Kernel 7.2 already has full in-tree Bluetooth support for it — btmtk.ko
  # references `mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin`, MT6639 and
  # mt7927 by name, and btusb matches MediaTek's 0489 vendor class. The ONLY
  # missing piece is the firmware blob itself: linux-firmware ships the two
  # MT7927 *WiFi* blobs (WIFI_RAM_CODE_MT6639_2_1.bin,
  # WIFI_MT6639_PATCH_MCU_2_1_hdr.bin) but not the Bluetooth one.
  #
  # Without it btusb retries the firmware load, wedges the BT function's onboard
  # state, and the wedged function then half-answers USB enumeration — the
  # `device descriptor read/64, error -110` storm on usb1-port8 that stalls the
  # whole root hub and, with it, the onboard USB audio card on 1-7.
  #
  # LICENSING: this blob is NOT redistributable-approved. linux-firmware MR !946
  # ("mediatek: Add MT6639 (MT7927) Bluetooth firmware") was CLOSED without
  # merging, pending MediaTek sign-off, and upstream `main` still carries only
  # the WiFi blobs. This pins the file from that MR's source branch. It is fine
  # for a personal host with this exact hardware; do not vendor it anywhere
  # public. Re-check whether it has landed upstream before carrying this
  # forward — if linux-firmware ever ships it, delete this whole block.
  mt7927BtFirmware = pkgs.runCommand "mt7927-bt-firmware" { } ''
    install -Dm444 ${
      pkgs.fetchurl {
        url = "https://gitlab.com/api/v4/projects/80012974/repository/files/mediatek%2Fmt7927%2FBT_RAM_CODE_MT6639_2_1_hdr.bin/raw?ref=77ad2a92acf2ac3e5ea47432b43d925ff99db909";
        hash = "sha256-ZpxcmaDFnIXBKF09G4sxkVwtMTQaIkT07dy/1g/7vHY=";
      }
    } $out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
  '';
in
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

  # Ship the missing MT7927 Bluetooth firmware (see the `let` block above).
  # This is the real fix for the long-standing "no audio or mic for ~45 s after
  # login" problem: with the blob present btusb can actually initialise the BT
  # function instead of wedging it, so usb1-port8 enumerates normally and stops
  # holding the root hub's device lock while the USB audio card waits to
  # register.
  #
  # NOTE: a wedged MT6639 survives a normal reboot. If the enumeration errors
  # persist after rebuilding, do a full power cycle — shut down, kill the PSU
  # switch or pull the cord for 10+ seconds — to reset the BT function's onboard
  # state. That is a documented quirk of this chip, not a config problem.
  #
  # The previous `usb1-port8` early_stop workaround is deliberately GONE. It only
  # ever halved the delay (64 s → 43 s, since the kernel ABI caps `early_stop` at
  # two initialisation attempts), and now that the port is meant to enumerate
  # successfully it would be actively harmful: a port marked early_stop that
  # fails once "will ignore all future connections until this attribute is
  # cleared", which would lock out the Bluetooth radio after any transient
  # failure.
  hardware.firmware = [ mt7927BtFirmware ];

  # The Wi-Fi half of the same MT7927 module needs nothing here. Kernel 7.2
  # claims 14c3:7927 (and 14c3:6639 / 14c3:0738) in-tree: mt7925e carries the
  # MT7927 chip IDs, firmware paths, its DMA ring layout and IRQ map, the ASPM
  # workaround and 320 MHz EHT. The out-of-tree mt76 rebuild that supplied all
  # of that on 7.1.8 (hosts/mt7927-mt76.nix) is gone as of the 7.2 bump.
}
