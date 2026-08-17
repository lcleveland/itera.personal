# Netskope Client for Linux — the corporate SASE/SSE endpoint agent (steers this
# machine's traffic through the lselectric tenant). Framework-only: the tenant is
# work infrastructure, so this file is imported from hosts/framework.nix rather
# than hosts/common.nix, and the flake module comes in through specialArgs
# (see flake.nix) instead of the every-host `modules` list.
#
# The module + packaging live in github:lcleveland/netskope-client. Upstream has now
# host-verified the parts that don't need tenant credentials — the package builds,
# every binary's libraries resolve, and stagentd + the tray user service start — and
# its VM test passes. Still unverified there: the enrollment handshake (needs the
# tenant org key + auth token, see below), and the bind-mount peer-path fix, which
# has only been exercised in the VM test against a stub package.
{
  netskope,
  config,
  pkgs,
  ...
}:
{
  imports = [ netskope.nixosModules.default ];

  # (The `services.netskope.package` workaround that used to sit here is gone: it
  # pinned `src = null` so that callPackage couldn't auto-fill the packaging
  # expression's `src ? null` argument from nixpkgs' throwing `pkgs.src` rename
  # alias. Upstream renamed that argument to `srcOverride`, which collides with
  # nothing in the package set, so the module's own default works and produces the
  # exact same derivation. Note it is now an *error* to pass `src` here.)

  services.netskope = {
    enable = true;

    # Short tenant name. The module derives both the installer URL
    # (https://download-lselectric.goskope.com/dlr/linux/get — public, no auth) and
    # `tenantHost` (addon-lselectric.goskope.com) from it.
    tenant = "lselectric";

    # Hash of the fetched NSClient.run. NOT universal — Netskope rebuilds the
    # installer per tenant and version, so this pins the exact build we packaged
    # (v140.0.2.2763). It changes whenever the tenant is moved to a new client
    # release, and the fetch then fails with a hash mismatch. Re-pin with:
    #
    #   nix store prefetch-file --name NSClient.run \
    #     "https://download-lselectric.goskope.com/dlr/linux/get"
    #
    # (Verified current as of 2026-08-17.) The client cannot self-update on NixOS
    # (immutable store), so bumping this hash IS the update path — which is why
    # `autoUpdate` is left at its default of false.
    hash = "sha256-lOAsV+/zV1KNZBraDw8qa7nL4SDu0GH3who7fgLhQTI=";

    # Tray UI (stAgentUI + the per-user stagentapp service). This is a desktop
    # host, and the tray is the only place the client surfaces its enrollment /
    # steering status, so keep it — it costs a GTK+WebKit closure. It is wired to
    # graphical-session.target; DankMaterialShell provides the StatusNotifier host.
    enableTray = true;

    # SSL-inspection root CA. Netskope MITMs TLS, so once steering is live anything
    # that doesn't trust this CA sees certificate errors. Deliberately OFF until the
    # tenant CA PEM is on disk — the installer does not ship it, so it can't be
    # derived from the package. To enable: get nstenantcert.crt from the admin
    # console (Settings -> Manage SSL Decryption, or copy it off an enrolled host —
    # under this module's state relocation it lands in /var/lib/netskope/data/),
    # place it somewhere persistent, then set:
    #
    #   trustCA = true;
    #   caCertFile = "/persist/etc/netskope/nstenantcert.crt";
    #
    # NB: caCertFile is a `path`, so its contents are copied into the world-readable
    # Nix store and baked into the system CA bundle at build time. That's fine for a
    # certificate (public by nature) but means the file must exist at eval time.

    # Declarative enrollment. LEFT UNCONFIGURED: it needs two tenant secrets that
    # aren't in this repo — the org key (Windows `token=`) and the secure-enrollment
    # auth token (Windows `enrollauthtoken=`), both from the admin console. Without
    # them the client is installed and the daemon runs, but the device never enrolls
    # — no tenant branding file is downloaded, and the tray/stAgentCli report it
    # unenrolled.
    #
    # To turn it on, drop the two values into root-only files that survive the
    # ephemeral root — /persist is the pragmatic spot (agenix is available through
    # itera if these should instead be committed encrypted):
    #
    #   sudo install -d -m 0700 /persist/secrets
    #   printf %s '<org key>'    | sudo install -m 0400 /dev/stdin /persist/secrets/netskope-orgkey
    #   printf %s '<auth token>' | sudo install -m 0400 /dev/stdin /persist/secrets/netskope-authtoken
    #
    # then uncomment:
    #
    #   enrollment = {
    #     orgKeyFile = "/persist/secrets/netskope-orgkey";
    #     authTokenFile = "/persist/secrets/netskope-authtoken";
    #   };
    #
    # These are `str`, not `path`, precisely so the secrets are read at runtime via
    # systemd LoadCredential and never enter the store. Don't enable this before the
    # files exist: netskope-enroll.service would fail on every boot (the daemon still
    # starts, since it only `wants` the enroll unit). Once the files are in place the
    # unit is self-verifying — it now checks that a branding file actually landed and
    # fails loudly instead of "succeeding" with the client still unenrolled.
  };

  # The package installs everything under $out/opt/netskope/stagent and ships no
  # $out/bin, so the module's `environment.systemPackages = [ cfg.package ]` puts no
  # commands on PATH — leaving no way to ask the client what it's doing.
  #
  # These symlinks MUST point at /opt/netskope/stagent rather than into the store.
  # The client's IPC layer (NSCom2) authenticates peers by resolving the connecting
  # process's /proc/<pid>/exe against a hard-coded allowlist of
  # /opt/netskope/stagent/{stAgentApp,stAgentCli,stAgentUI,nsdiag,bwansvc} — the
  # constraint that forced upstream to bind-mount the app dir instead of symlinking
  # binaries in from the store. Verified: exec'ing through this symlink chain
  # (/run/current-system/sw/bin -> store -> /opt) makes /proc/<pid>/exe read back as
  # /opt/netskope/stagent/stAgentCli, so the peer check passes; a store-resident copy
  # would report a /nix/store/... path and be rejected with "NSCOM2 invalid client
  # connection".
  environment.systemPackages = [
    (pkgs.runCommandLocal "netskope-cli" { } ''
      mkdir -p $out/bin
      ln -s /opt/netskope/stagent/stAgentCli $out/bin/stAgentCli
      ln -s /opt/netskope/stagent/nsdiag $out/bin/nsdiag
    '')
  ];

  # Impermanence. The client hard-codes /opt/netskope/stagent and writes its state
  # there, so upstream keeps the real directory at `statePath`/app and bind-mounts it
  # onto that path (a bind, not a symlink, so /proc/<pid>/exe keeps the hard-coded
  # path the IPC peer check demands — see the CLI note above). That makes statePath
  # the single thing an impermanent host has to persist: it holds the device identity
  # (.mid, provisioning), the config, the enrollment result, and data/ + logs/.
  # itera's curated persist list doesn't cover it, so declare it here — otherwise
  # every reboot looks like a fresh install to Netskope.
  #
  # This entry is ALSO load-bearing for the daemon starting at all, which is easy to
  # miss. itera bind-mounts /var with noexec, and since the rework the app dir holds
  # REAL ELF binaries (previously they were symlinks into /nix/store, which execs
  # from the store's own mount). Verified on the live host: a binary in a plain
  # directory under the noexec /var fails to exec (126), while a bind mount whose
  # source is the exec-capable /persist subvolume runs fine — mount flags are
  # per-mount and are NOT inherited from the parent mount — and netskope-setup's
  # second bind (app -> /opt) preserves that. Drop this entry and stagentd dies on
  # exec, not merely on lost state.
  #
  # Ordering is handled upstream: netskope-setup carries
  # RequiresMountsFor=/var/lib/netskope, so it waits for the bind mount below.
  #
  # Nothing under /opt is persisted, and it must stay that way — those files are
  # refreshed from the store whenever the package changes, and a persisted /opt would
  # shadow the bind mount. Mode 0700 on statePath is deliberate and safe: nothing
  # reaches the state through this path. The per-user stAgentUI/stAgentCli read
  # data/nsusercert.p12 via /opt/netskope/stagent/data, so they never traverse
  # statePath itself, and netskope-setup sets app/, data/ and logs/ to 0755 inside.
  itera.impermanence.directories = [
    {
      # Tracks the module's own option so the two can't drift apart.
      directory = config.services.netskope.statePath;
      mode = "0700";
    }
  ];
}
