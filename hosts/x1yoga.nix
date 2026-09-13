# x1yoga — Lenovo ThinkPad X1 Yoga Gen 8 work laptop (hostname CHANGE-ME).
#
# Same ROLE as `framework` (the work tenant: Netskope, Falcon, smartcard reader,
# FDE + TPM2, Colemak-DH, printing, fingerprint), different HARDWARE: a 13th-gen
# Intel convertible instead of the AMD Framework 16. The work-app trio is shared
# from ./apps/work/ rather than duplicated — nothing in those files is specific
# to a laptop model, only to the tenant.
{ itera, ... }:
{
  # ThinkPad X1 Yoga Gen 8 hardware quirks, re-exported by itera from
  # nixos-hardware. Board selection is an import-time choice the module system
  # can't toggle from config, so it goes in `imports` rather than `itera.*`.
  #
  # What the import chain hands us (8th-gen -> x1/yoga -> x1 -> thinkpad ->
  # common/pc/laptop, plus common/pc/ssd):
  #   - common/cpu/intel                 microcode + Intel graphics defaults
  #   - common/pc/ssd                    periodic fstrim
  #   - hardware.trackpoint.*            TrackPoint + middle-button wheel emulation
  #   - services.fprintd / services.fwupd
  #   - hardware.sensor.iio.enable       accelerometer -> automatic screen rotation,
  #                                      which is the point of the convertible
  # The chain also sets services.xserver.wacom, but that is gated on
  # services.xserver.enable and we run mango/Wayland, so it is inert. The pen and
  # touchscreen themselves are plain evdev/libinput and need nothing here.
  imports = [
    itera.hardwareModules.lenovo-thinkpad-x1-yoga-8th-gen
    # Work-tenant apps, shared with `framework` — see the note at the top.
    ./apps/work/smartcard-reader.nix
    # Corporate Netskope client (work tenant only, hence not in common.nix).
    ./apps/work/netskope.nix
    # Corporate CrowdStrike Falcon EDR sensor (work tenant only, as above).
    ./apps/work/falcon-sensor.nix
  ];

  itera = {
    networking.hostName = "CHANGE-ME"; # asset tag, as LS-04380 is for framework

    # Overrides the "amd" that hosts/common.nix sets for both other machines.
    # Not cosmetic: this selects the microcode package and the `kvm-*` module.
    hardware.cpu = "intel";

    # This host is nixosConfigurations.x1yoga; the hostname differs from the
    # flake attribute, so set it explicitly (else `itera update`/`rebuild` would
    # pass `--hostname <hostname>` and miss `#x1yoga`).
    update.configuration = "x1yoga";

    # Deliberately-invalid placeholder so the config still evaluates (satisfies
    # itera.disko's non-empty-device assertion) WITHOUT hardcoding a real disk.
    # `disko-install --disk main /dev/<real>` overrides this at install time, so
    # you never edit this file to install — and a forgotten `--disk` fails safe
    # (disko errors on the bogus path instead of wiping a real disk).
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "32G"; # >= RAM for hibernation

    # Full-disk encryption (LUKS): wraps the btrfs root AND the swap partition, so
    # everything at rest — /, /nix, /persist, and the hibernation image in swap —
    # is encrypted; only the ESP stays readable for firmware. Both containers share
    # one passphrase. Opt-in and off by default upstream (it changes the on-disk
    # format), so enable it explicitly here.
    #
    # passwordFile points at an install-time-only path. The installer prompts for a
    # new passphrase and writes it there just before formatting, then reuses the same
    # file to enroll the TPM2 keyslot (below) in one pass — so the first boot is
    # already passwordless with no post-install step. The file lives only on the
    # live ISO's tmpfs and is shredded when the installer exits; disko reads it at
    # format time only (never post-install), so no key lands on the target disk.
    # The passphrase you type becomes the TPM2 recovery fallback (see below).
    disko.encryption.enable = true;
    disko.encryption.passwordFile = "/tmp/itera-luks.key";

    # TPM2 auto-unlock (itera change): a keyslot sealed to the machine's TPM2 (PCR
    # 7 = Secure Boot state) unlocks both containers with NO passphrase on a trusted
    # boot; the passphrase set at install stays enrolled as a recovery fallback if
    # the sealed PCR state changes. Enrollment binds to the live TPM, so it runs on
    # this machine — the installer does it right after formatting, using the
    # passphrase you just typed, so there is no post-install step. (After a firmware
    # or Secure Boot change invalidates the sealed PCR state, re-run
    # `sudo itera-tpm2-enroll`.)
    #
    # SECURITY: with itera.secureBoot OFF (still the case here — it needs a manual,
    # per-machine setup-mode key enrollment that a scripted install can't do), TPM2
    # unlock protects a *pulled* disk but NOT a thief who just powers the laptop on.
    # To close that gap, enable itera.secureBoot and enroll keys (`sbctl create-keys`
    # / `sbctl enroll-keys --microsoft`), then re-run `itera-tpm2-enroll`.
    disko.encryption.tpm2.enable = true;

    # NOTE: no `hardware.initrd.usbSupport` line, unlike framework.nix. itera
    # already force-defaults it on whenever encryption is enabled (TPM2 or not),
    # so the recovery-passphrase prompt has a keyboard either way — and this
    # machine's built-in keyboard is i8042, which stage 1 has regardless.

    # On by default, but worth a look on first boot: fprintd drives the reader
    # through libfprint, and the Validity/Synaptics VFS7552 family (138a:* /
    # 06cb:* chips, common on ThinkPads) has no libfprint driver. If
    # `fprintd-enroll` says "No devices available", check the reader's id with
    # `lsusb` and set this to false rather than leaving a dead battery enabled.
    fingerprint.enable = true;
    printing.enable = true; # itera default: hplipWithPlugin + mDNS + GUI

    # Colemak-DH across console + mango session + greeter, same as framework.
    keyboard.layout = "us";
    keyboard.variant = "colemak_dh";

    # No `programs.mango.monitors` on purpose: mango auto-detects the internal
    # panel, and the X1 Yoga Gen 8 ships several (WUXGA IPS / 2.8K OLED / 4K).
    # Add an explicit layout here once the docked setup is known, copying the
    # shape from hosts/framework.nix.

    # Pointer input. Neither knob is a curated itera option, so they go through
    # the per-user `extraConfig` escape hatch, which the hjem renderer appends
    # verbatim to ~/.config/mango/config.conf (last section in the file).
    #
    #   *_natural_scrolling  mango defaults BOTH to 0 (content moves opposite the
    #                        fingers/wheel). 1 = natural/"content follows the
    #                        gesture", the macOS-style direction. Set on the
    #                        trackpad AND the external mouse so the direction is
    #                        the same whichever pointer is in hand.
    #   sloppyfocus          mango defaults it to 1 — focus follows the cursor, so
    #                        merely passing the pointer over a window steals focus
    #                        from what you were typing in. 0 = click to focus.
    users.lcleveland.programs.mango.extraConfig = ''
      trackpad_natural_scrolling=1
      mouse_natural_scrolling=1
      sloppyfocus=0
    '';
    # nvidia stays OFF (itera.nvidia is opt-in / default false).
  };
}
