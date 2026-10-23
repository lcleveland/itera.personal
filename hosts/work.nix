# Work-tenant role: imported by framework and x1yoga. Everything here belongs to
# the work tenant (its endpoint agents, its network-only MCP servers, the FDE
# policy and office printing), not to a laptop model, so a new work laptop takes
# this one import instead of a copy of these lines.
{
  imports = [
    # Corporate Netskope client (work tenant only, hence not in common.nix).
    ./apps/work/netskope.nix
    # Corporate CrowdStrike Falcon EDR sensor (work tenant only, as above).
    ./apps/work/falcon-sensor.nix
    # NetBox MCP server (work network only, as above).
    ./apps/work/netbox-mcp.nix
    # AD + Entra ID MCP server (the domain controllers are work network only).
    ./apps/work/microsoft-directory-mcp.nix
  ];

  itera = {
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

    printing.enable = true; # itera default: hplipWithPlugin + mDNS + GUI (matches eiros work)
  };
}
