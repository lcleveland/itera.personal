# framework — Framework 16 work laptop (eiros hostname LS-04380).
{ itera, ... }:
{
  # Framework 16 (AMD Ryzen 7040) hardware quirks, re-exported by itera from
  # nixos-hardware. Board selection is an import-time choice the module system
  # can't toggle from config, so it goes in `imports` rather than `itera.*`.
  imports = [
    itera.hardwareModules.framework-16-7040-amd
    # Framework-only apps, migrated from the old eiros.users.work repo.
    ./apps/framework/smartcard-reader.nix
  ];

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

    # Full-disk encryption (LUKS): wraps the btrfs root AND the swap partition, so
    # everything at rest — /, /nix, /persist, and the hibernation image in swap —
    # is encrypted; only the ESP stays readable for firmware. Both containers share
    # one passphrase. Opt-in and off by default upstream (it changes the on-disk
    # format), so enable it explicitly here.
    #
    # passwordFile points at an install-time-only path. install.sh prompts for a new
    # passphrase and writes it there just before formatting, then reuses the same
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
    # this machine — install.sh does it right after formatting, using the passphrase
    # you just typed, so there is no post-install step. (After a firmware or Secure
    # Boot change invalidates the sealed PCR state, re-run `sudo itera-tpm2-enroll`.)
    #
    # SECURITY: with itera.secureBoot OFF (still the case here — it needs a manual,
    # per-machine setup-mode key enrollment that a scripted install can't do), TPM2
    # unlock protects a *pulled* disk but NOT a thief who just powers the laptop on.
    # To close that gap, enable itera.secureBoot and enroll keys (`sbctl create-keys`
    # / `sbctl enroll-keys --microsoft`), then re-run `itera-tpm2-enroll`.
    disko.encryption.tpm2.enable = true;

    # The Framework 16's built-in keyboard is internally USB-connected. itera
    # force-enables initrd.usbSupport when encryption is on, but DROPS that force-on
    # once TPM2 is enabled (nothing is typed on the happy path). Re-enable it
    # explicitly: without USB HID in the initrd, the recovery-passphrase fallback
    # (when the TPM refuses to unseal) would have no keyboard and lock us out.
    hardware.initrd.usbSupport = true;

    fingerprint.enable = true; # on by default; explicit for clarity
    printing.enable = true; # itera default: hplipWithPlugin + mDNS + GUI (matches eiros work)

    # Colemak-DH across console + mango session + greeter (eiros keyboard_layout.nix).
    keyboard.layout = "us";
    keyboard.variant = "colemak_dh";

    # Monitor layout (origin top-left, +x right / +y down):
    #   eDP-1 laptop on the left, bottom-aligned with the ultrawide.
    #   DP-11 49" super-ultrawide (5120x1440 @165) to the right of the laptop.
    #   DP-10 Lenovo T24i-10 (upside down) flush above the ultrawide's top-left
    #     corner (edges meet at y=1080, no overlap).
    programs.mango.monitors = {
      "eDP-1" = {
        width = 2560;
        height = 1600;
        refresh = 165;
        x = 0;
        y = 920; # bottom-aligned with DP-11 (1080 + 1440 - 1600)
      };
      "DP-10" = {
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 2560; # left-aligned with DP-11
        y = 0; # sits directly above DP-11 (bottom edge at y=1080)
        transform = "180"; # panel physically mounted upside down
      };
      "DP-11" = {
        width = 5120;
        height = 1440;
        refresh = 165;
        x = 2560; # right of the laptop
        y = 1080; # below DP-10
      };
    };
    # nvidia stays OFF (itera.nvidia is opt-in / default false) — matches eiros.
  };
  # SKIPPED (per user): MT7922 Bluetooth softdep/autosuspend quirks; 3-finger
  # gesturebinds and trackpad flags can be added later if wanted (not essentials).
}
