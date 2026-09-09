# CrowdStrike Falcon sensor — the corporate EDR agent. Framework-only: like
# netskope this is work-tenant infrastructure, so the file is imported from
# hosts/framework.nix rather than hosts/common.nix, and the flake module comes in
# through specialArgs (see flake.nix) instead of the every-host `modules` list.
#
# The module + packaging live in github:lcleveland/falcon-sensor. Two NixOS-specific
# problems it exists to solve, both relevant to how this file is written:
#
#   - The installer is behind an authenticated API and cannot be fetched during a
#     build, so the package is a `requireFile` against a pin in the flake's
#     pkgs/sources.json. See the flake.nix input comment for the one-time store step.
#   - falcond hard-codes /opt/CrowdStrike and writes its identity there. The module
#     keeps the real directory at `statePath`/opt and bind-mounts it onto that path
#     (a bind, not a symlink, because an EDR resolves identities through
#     /proc/<pid>/exe and a store path would read back wrong). That makes statePath
#     the single thing this impermanent host has to persist — see the bottom of
#     this file.
#
# Upstream status, worth knowing before trusting this: verified end-to-end against a
# real tenant at build time (API auth, CID lookup, installer selection, checksum,
# store pin, a clean autoPatchelfHook build) and covered by an 11-subtest NixOS VM
# test — but NOT yet run on real hardware. Whether autoPatchelfHook's ELF rewriting
# upsets the sensor's own integrity checking can only be answered by starting
# falcond here.
{
  falcon-sensor,
  config,
  ...
}:
{
  imports = [ falcon-sensor.nixosModules.default ];

  services.falcon-sensor = {
    enable = true;

    # CID (Customer ID) — the tenant this host registers against. Upstream treats a
    # plaintext `cid` as acceptable (it identifies the tenant, it does not
    # authenticate), but this repository is public, so use the file form and keep
    # the value out of the store entirely. Same convention as netskope's secrets:
    # a root-only file under /persist, which survives the ephemeral root and is on
    # a real mount that is up long before this unit runs. Create it before the
    # first rebuild that enables this:
    #
    #   sudo install -d -m 0700 /persist/secrets
    #   printf %s '<CID>' | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-cid
    #
    # The option is `str`, not `path`, precisely so the value is read at runtime via
    # systemd LoadCredential — it appears in no unit file, no nixos-rebuild log and
    # no journal entry. The module asserts at eval time against any value under
    # /nix/store. `nix run github:lcleveland/falcon-sensor#update-sensor` prints the
    # CID for the API credentials it authenticated with, if you need to look it up.
    #
    # Without this file falcon-sensor-configure.service fails on every boot; the
    # daemon then fails too, since it `requires` the configure unit (and the vendor
    # unit's own ExecStartPre is `falconctl -g --cid`).
    cidFile = "/persist/secrets/falcon-cid";

    # NOT set: provisioningTokenFile. Only tenants that require an installation
    # token to register a host need it, and setting it would make the configure unit
    # fail on a missing credential file. If registration is refused without one, add
    # /persist/secrets/falcon-provisioning-token the same way as the CID above and
    # set `provisioningTokenFile` to it. maintenanceTokenFile is likewise only
    # needed once sensor tamper protection is turned on for this host.

    # Use the falcon-sensor.service that ships inside the .deb rather than the
    # module's reconstruction of it. Upstream defaults this to false only because a
    # .deb that installed its unit from a postinst script would leave you with no
    # service at all — that is not this .deb. Verified against the pinned build:
    #
    #   ls ${config.services.falcon-sensor.package}/lib/systemd/system/
    #   -> falcon-sensor.service
    #
    # so the vendor's own Type/PIDFile/KillMode/Delegate settings are used verbatim
    # and the module's unit becomes a drop-in that adds only ordering. The setup
    # service also re-checks this at runtime and fails loudly if the file is absent
    # (it can't be an eval-time assertion without an import-from-derivation).
    #
    # One consequence to be aware of: the vendor sets `Restart=no`, so a crashed
    # sensor stays down, where the module's own unit would default to `on-failure`.
    # The `restart` option is inert while useVendorUnit is on; to change it, add a
    # `systemd.services.falcon-sensor.serviceConfig.Restart` drop-in here instead.
    useVendorUnit = true;

    # `backend` is left at its "bpf" default deliberately. The eBPF backend runs in
    # user space and has far looser kernel requirements than the "kernel" backend,
    # which wants a module built against a kernel on CrowdStrike's supported list —
    # which a NixOS kernel generally is not. The module warns if you set "kernel".
    #
    # EXPECT REDUCED FUNCTIONALITY MODE. The sensor validates the running kernel
    # against that same supported list and falls back to RFM when it isn't on it, so
    # this host will most likely report heartbeats and asset inventory but perform no
    # detection or prevention. No packaging choice avoids that; it is CrowdStrike's
    # call. Check what actually happened after the first boot with:
    #
    #   /opt/CrowdStrike/falconctl -g --rfm-state --rfm-reason --version --aid
    #   falcon-kernel-check
    #
    # Both are on PATH: the module puts the package in environment.systemPackages and
    # it ships $out/bin symlinks. Note that falconctl writes to /var/log/falconctl.log
    # as well as the journal — that survives reboots here, since itera's curated
    # impermanence defaults already persist /var/log.

    # `autoRemoveAid` stays off (the default). It clears the Agent ID on every start,
    # which is right for golden images and exactly wrong for a persisted laptop: it
    # would defeat the state directory below and re-register this machine as a new
    # device each boot.
  };

  # Impermanence. Everything mutable lives under `statePath` (/var/lib/falcon-sensor):
  # the device identity in `falconstore` — which carries the AID — the configuration
  # falconctl writes, and the channel files the sensor downloads. Without this entry
  # the sensor loses its AID on every boot, re-registers as a brand-new host, and
  # re-downloads every channel file. itera's curated persist list doesn't cover it,
  # so declare it here.
  #
  # This entry is ALSO load-bearing for the daemon starting at all — the same trap
  # netskope hit, for the same reason. itera bind-mounts /var as a noexec tmpfs
  # (verified on this host: `findmnt /var` -> nosuid,nodev,noexec), and `statePath`/opt
  # holds REAL ELF binaries copied out of the store, not symlinks into it. Mount flags
  # are per-mount and are NOT inherited from the parent, so a plain directory under
  # /var would refuse to exec falcond (126), while a bind mount whose source is the
  # exec-capable /persist subvolume runs fine — and the module's second bind
  # (`statePath`/opt -> /opt/CrowdStrike) preserves that. Drop this entry and the
  # sensor dies on exec, not merely on lost state.
  #
  # Nothing under /opt is persisted, and it must stay that way: those files are
  # refreshed from the store on every activation, and a persisted /opt would shadow
  # the bind mount.
  #
  # Ordering needs nothing extra from us — impermanence's binds are real mounts
  # ordered Before=local-fs.target, and all three of the module's units additionally
  # carry RequiresMountsFor=statePath.
  #
  # Upstream deliberately does not set persistence itself (impermanence asserts on
  # duplicate paths, so a module contributing a path you also listed would break
  # evaluation) and instead exposes the read-only `persistedPaths`. Use that rather
  # than hardcoding /var/lib/falcon-sensor, so the two can't drift apart.
  itera.impermanence.directories = config.services.falcon-sensor.persistedPaths;
}
