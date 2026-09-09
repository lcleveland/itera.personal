# CrowdStrike Falcon sensor — the corporate EDR agent. Framework-only: like
# netskope this is work-tenant infrastructure, so the file is imported from
# hosts/framework.nix rather than hosts/common.nix, and the flake module comes in
# through specialArgs (see flake.nix) instead of the every-host `modules` list.
#
# The module + fetch tool live in github:lcleveland/falcon-sensor. Two
# NixOS-specific problems it exists to solve, both of which shape this file:
#
#   - The installer is behind an authenticated API and can never be fetched during
#     a build, so it is not packaged at all. Each host downloads its own copy at
#     runtime, authenticating with an API client id + secret. That is why the two
#     `api.*File` options below are mandatory — the module asserts on them.
#   - falcond hard-codes /opt/CrowdStrike and writes its identity there. The fetch
#     unit installs into `statePath`/opt and bind-mounts that onto the hard-coded
#     path (a bind, not a symlink, because an EDR resolves identities through
#     /proc/<pid>/exe, and because the .deb's files are read-only while the sensor
#     writes into its own subdirectories at runtime). That makes statePath the
#     single thing this impermanent host has to persist — see the bottom of this file.
#
# VERIFIED ON THIS HOST, 2026-09-09 — this file is no longer the "not yet run on
# real hardware" case upstream's README describes. Measured on kernel 7.2.3:
# authenticated to api.us-2.crowdstrike.com, selected and downloaded
# falcon-sensor_8.10.0-19402_amd64.deb, verified its sha256 against the `hash`
# below, patched 11 ELF objects for this host, installed into statePath/opt and
# bind-mounted it onto /opt/CrowdStrike. falcond then started clean with a
# falcon-sensor-bpf child, and the tenant issued an AID.
#
# That answers upstream's headline open question: the runtime ELF patching does NOT
# upset the sensor's own integrity checking. It also means the whole fetch path —
# not just the API half the live run covered — is now exercised outside the VM
# test's stub.
{
  falcon-sensor,
  config,
  ...
}:
{
  imports = [ falcon-sensor.nixosModules.default ];

  services.falcon-sensor = {
    enable = true;

    # Which sensor to install, as the SRI hash of its .deb. CrowdStrike's download
    # endpoint is keyed by that same SHA-256 (?id=<sha256>), so this one value both
    # selects the installer and verifies it — there is nothing else to pin, and
    # bumping this IS the upgrade path.
    #
    # This is 8.10.0-19402, the build upstream verified against the live tenant.
    # List what this tenant can install, each with the line to paste here:
    #
    #   nix run github:lcleveland/falcon-sensor#find-sensor -- \
    #     --client-id-file <id file> --client-secret-file <secret file>
    #
    # Leaving it null is supported but the module warns, and rightly: the host would
    # install whatever the API offers at first boot, so two machines built from the
    # same config could land on different sensors, and every boot would have to ask
    # the API which one to use. With it set, a host that already has this sensor does
    # NO network I/O at boot — the .installed-hash check happens before authentication.
    hash = "sha256-RVNTBhFgWCM2y2bT4POM6btnvXiOFReoL1LvODFvVs8=";

    # Sensor Download API credentials. Mandatory: the module asserts on both, since
    # without them the host cannot download the sensor at all.
    #
    # ACCEPT THE TRADE-OFF KNOWINGLY. A client that can download installers for the
    # whole tenant now lives on this laptop permanently. Scope it to
    # "Sensor Download: read" and NOTHING else, so a stolen credential can fetch
    # installers and do nothing more. Do not reuse a client that also carries
    # sensor-update-policy or host-management scopes.
    #
    # Same convention as the CID and netskope's secrets: root-only files under
    # /persist, which survive the ephemeral root and sit on a real mount that is up
    # long before this unit runs. Both are `str`, not `path`, so the values are read
    # at runtime via systemd LoadCredential and never enter the store, a unit file or
    # the journal; the module asserts at eval time against any value under /nix/store.
    # They are also never passed as arguments, since argv is readable through /proc.
    #
    #   sudo install -d -m 0700 /persist/secrets
    #   printf %s '<client id>'     | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-api-client-id
    #   printf %s '<client secret>' | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-api-client-secret
    #
    # Without these files falcon-sensor-fetch.service fails; it retries every 300s
    # rather than leaving the host sensorless until the next reboot.
    api.clientIdFile = "/persist/secrets/falcon-api-client-id";
    api.clientSecretFile = "/persist/secrets/falcon-api-client-secret";

    # NOT set: api.updatePolicy. It would take the version from a sensor update
    # policy rather than the pinned `hash`, which is how you would track the tenant's
    # own N-1/N-2 rollout — but it needs the "Sensor update policies: read" scope on
    # the API client above, and it only takes effect when `hash` is null. Pinning is
    # the deliberate choice here: the deployed sensor stays described by this file.
    # api.cloud is likewise unset, so the region is discovered from the X-Cs-Region
    # header on each run.

    # CID (Customer ID) — the tenant this host registers against. Upstream treats a
    # plaintext `cid` as acceptable (it identifies the tenant, it does not
    # authenticate), but this repository is public, so use the file form and keep the
    # value out of the store entirely. Create it alongside the API credentials above:
    #
    #   printf %s '<CID>' | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-cid
    #
    # `find-sensor` prints the CID next to the available sensors, so you rarely need
    # to dig it out of the console. Without this file falcon-sensor-configure.service
    # fails on every boot, and the daemon fails with it — it `requires` the configure
    # unit, and the vendor's own ExecStartPre is `falconctl -g --cid`.
    cidFile = "/persist/secrets/falcon-cid";

    # NOT set: provisioningTokenFile. Only tenants that require an installation token
    # to register a host need it, and setting it would make the configure unit fail on
    # a missing credential file. If registration is refused without one, add
    # /persist/secrets/falcon-provisioning-token the same way and point the option at
    # it. maintenanceTokenFile is likewise only needed once sensor tamper protection
    # is turned on for this host.

    # `backend` is left at its "bpf" default deliberately. The eBPF backend runs in
    # user space and has far looser kernel requirements than the "kernel" backend,
    # which wants a module built against a kernel on CrowdStrike's supported list —
    # which a NixOS kernel generally is not. The module warns if you set "kernel".
    #
    # RFM: NOT happening here, against every expectation. The sensor validates the
    # running kernel against that same supported list and falls back to Reduced
    # Functionality Mode when it isn't on it, and upstream's README says to expect
    # exactly that on a NixOS kernel. Measured on this host instead:
    #
    #   rfm-state=false, rfm-reason=None, code=0x0
    #
    # on kernel 7.2.3 with the bpf backend — so the sensor is fully operational, doing
    # real detection and prevention rather than only heartbeats and inventory. Do not
    # treat that as guaranteed across kernel bumps: this is CrowdStrike's supported-
    # kernel list, it moves without reference to us, and a NixOS kernel update is
    # exactly the kind of change that can silently drop the host into RFM. Re-check
    # after kernel upgrades with:
    #
    #   sudo /opt/CrowdStrike/falconctl -g --rfm-state --rfm-reason --version --aid
    #   sudo /opt/CrowdStrike/falcon-kernel-check
    #
    # Note the absolute paths: the sensor is no longer a Nix package, so nothing of
    # its own lands on PATH. The only thing the module installs system-wide is the
    # `falcon-sensor-fetch` tool. falconctl also writes to /var/log/falconctl.log —
    # that survives reboots here, since itera's curated impermanence defaults already
    # persist /var/log.

    # `restart` is left at the module's "on-failure" default, which deliberately
    # differs from the vendor's `Restart=no` so a crashed security agent comes back.
    # Set it to "no" to match CrowdStrike's shipped unit exactly.

    # `autoRemoveAid` stays off (the default). It clears the Agent ID on every start,
    # which is right for golden images and exactly wrong for a persisted laptop: it
    # would defeat the state directory below and re-register this machine as a new
    # device each boot. The module warns if you enable it.
  };

  # Impermanence. Everything mutable lives under `statePath` (/var/lib/falcon-sensor):
  # the device identity in `falconstore` — which carries the AID — the configuration
  # falconctl writes, the channel files the sensor downloads, and now the installed
  # sensor itself. itera's curated persist list doesn't cover it, so declare it here.
  #
  # This entry does three jobs, and losing any one of them hurts:
  #
  #   1. Identity. Without it the sensor loses its AID every boot and re-registers as
  #      a brand-new host.
  #   2. Exec. This is the same trap netskope hit, for the same reason. itera
  #      bind-mounts /var as a noexec tmpfs (verified on this host: `findmnt /var`
  #      -> nosuid,nodev,noexec), and `statePath`/opt holds REAL ELF binaries.
  #      Mount flags are per-mount and are NOT inherited from the parent, so a plain
  #      directory under /var would refuse to exec falcond (126), while a bind mount
  #      whose source is the exec-capable /persist subvolume runs fine — and the
  #      module's second bind (`statePath`/opt -> /opt/CrowdStrike) preserves that.
  #   3. Bandwidth. Since the redesign the sensor is downloaded from the API rather
  #      than built into the closure, and the `.installed-hash` guard that makes a
  #      steady-state boot do zero network I/O lives in this directory. Drop it and
  #      every single boot re-authenticates and re-downloads the whole .deb.
  #
  # Nothing under /opt is persisted, and it must stay that way: it is reconstructed
  # on every boot, and a persisted /opt would shadow the bind mount.
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
