# x1yoga — Lenovo ThinkPad X1 Yoga Gen 8 work laptop (hostname CHANGE-ME).
#
# Same ROLE as `framework` (the work tenant: Netskope, Falcon, smartcard reader,
# FDE + TPM2, Colemak-DH, printing, fingerprint), different HARDWARE: a 13th-gen
# Intel convertible instead of the AMD Framework 16. The work-tenant role is
# shared through ./work.nix rather than duplicated — nothing in it is specific
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
    # Work-tenant role (see the note at the top).
    ./work.nix
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

    # NOTE: no `hardware.initrd.usbSupport` line, unlike framework.nix. itera
    # already defaults it on whenever encryption is enabled (TPM2 or not; see work.nix),
    # so the recovery-passphrase prompt has a keyboard either way — and this
    # machine's built-in keyboard is i8042, which stage 1 has regardless.

    # On by default, but worth a look on first boot: fprintd drives the reader
    # through libfprint, and the Validity/Synaptics VFS7552 family (138a:* /
    # 06cb:* chips, common on ThinkPads) has no libfprint driver. If
    # `fprintd-enroll` says "No devices available", check the reader's id with
    # `lsusb` and set this to false rather than leaving a dead battery enabled.
    fingerprint.enable = true;

    # Colemak-DH across console + mango session + greeter, same as framework.
    keyboard.layout = "us";
    keyboard.variant = "colemak_dh";

    # No `programs.mango.monitors` on purpose: mango auto-detects the internal
    # panel, and the X1 Yoga Gen 8 ships several (WUXGA IPS / 2.8K OLED / 4K).
    # Add an explicit layout here once the docked setup is known, copying the
    # shape from hosts/framework.nix.

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
    # nvidia stays OFF (itera.nvidia is opt-in / default false).
  };
}
