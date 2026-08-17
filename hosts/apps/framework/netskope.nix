# Netskope Client for Linux — the corporate SASE/SSE endpoint agent (steers this
# machine's traffic through the lselectric tenant). Framework-only: the tenant is
# work infrastructure, so this file is imported from hosts/framework.nix rather
# than hosts/common.nix, and the flake module comes in through specialArgs
# (see flake.nix) instead of the every-host `modules` list.
#
# The module + packaging live in github:lcleveland/netskope-client. Upstream flags
# it as NOT yet run-verified on a real Nix host, and the enrollment handshake in
# particular is untested — see the enrollment block below before trusting it.
{
  netskope,
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
    # — no .eetk token is written, and the tray/stAgentCli report it unenrolled.
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
    # starts, since it only `wants` the enroll unit).
  };

  # The package installs everything under $out/opt/netskope/stagent and ships no
  # $out/bin, so the module's `environment.systemPackages = [ cfg.package ]` puts no
  # commands on PATH — leaving no way to ask the client what it's doing. Expose the
  # two user-facing tools. They point at the materialised /opt path on purpose (not
  # the store): the client resolves its state relative to its own location, so a CLI
  # invoked from the store would look for config in a read-only directory.
  environment.systemPackages = [
    (pkgs.runCommandLocal "netskope-cli" { } ''
      mkdir -p $out/bin
      ln -s /opt/netskope/stagent/stAgentCli $out/bin/stAgentCli
      ln -s /opt/netskope/stagent/nsdiag $out/bin/nsdiag
    '')
  ];

  # Impermanence: the root is tmpfs, so without this every reboot looks like a fresh
  # install to Netskope. The module redirects the client's hard-coded writable state
  # (/opt/netskope/stagent/{data,logs}, which upstream expects to be mutable) to
  # /var/lib/netskope, and itera's curated persist list does not cover it. data/
  # holds the provisioned certs, the client config, and the .eetk enrollment token,
  # so persisting this directory is what makes enrollment survive the wiped root.
  # Mode 0700 to match what netskope-setup.service creates for data/ (secrets).
  #
  # /opt/netskope/stagent itself is intentionally NOT persisted: netskope-setup
  # re-materialises it from the store on every boot and switch, which is what keeps
  # it in sync across nixpkgs bumps. If enrollment turns out to re-run on every boot,
  # the cause is the client writing .eetk into that top directory instead of data/
  # (the enroll unit checks both paths) — persist "/opt/netskope/stagent" then.
  itera.impermanence.directories = [
    {
      directory = "/var/lib/netskope";
      mode = "0700";
    }
  ];
}
