# netskope-mcp — an MCP server over the Netskope REST API v2, so Claude Code can
# answer questions about the lselectric tenant (Private Access publishers and
# apps, NPA + inline policy, URL lists, event and alert search, SCIM identity)
# instead of us clicking through the admin UI.
#
# Every host, unlike apps/work/netskope.nix next door. The two are unrelated
# despite the name: that one is the *endpoint agent* that steers this machine's
# traffic and is only meaningful on a work laptop, this is an API *client* that
# needs nothing but a token and network. Being able to ask about the tenant from
# dream is the point, so the module is imported for all hosts in flake.nix
# (alongside ninjarmm-ncplayer) rather than through specialArgs.
#
# The packaging + module live in github:lcleveland/netskope-mcp. Built from Go
# source, MIT: the first from-source build in this set of flakes, so `go.mod`
# changes need a `vendorHash` refresh upstream, not here.
{
  # Loopback HTTP on the default 127.0.0.1:8231/mcp, which is what makes this a
  # one-line client config on every host instead of a per-client command + args.
  # No bearerTokenFile and no openFirewall deliberately: nothing off this machine
  # can reach the socket, and the module asserts if we ever open the port without
  # moving the listener off loopback.
  #
  # Register it with Claude Code ONCE per host (it writes ~/.claude.json, which
  # itera's impermanence persistence already carries, so it survives the wiped
  # root — there is nothing declarative to do here):
  #
  #   claude mcp add --scope user --transport http netskope http://127.0.0.1:8231/mcp
  #
  # Deliberately NOT /etc/claude-code/managed-mcp.json, the enterprise config that
  # *would* be declarative: an enterprise MCP config takes exclusive control of
  # MCP servers and suppresses every user-, project- and plugin-scoped one, so
  # declaring this server that way would silently disable all the others.
  services.netskope-mcp = {
    enable = true;

    # Short tenant name, expanded to https://lselectric.goskope.com. This is the
    # bare tenant host, NOT the addon- host the client's Windows deployment string
    # uses (see apps/work/netskope.nix) — different API, different hostname.
    tenant = "lselectric";

    # The REST API v2 token, read at runtime through systemd LoadCredential, so it
    # never enters the store, the unit's Environment=, argv, or a rebuild log.
    # `str` rather than `path` precisely so that stays true. Root-only file on
    # /persist, same place and reasoning as the netskope client's two tenant
    # secrets; create it before the first rebuild that enables this, on EVERY host
    # (the unit fails on boot without it — the daemon holds no state, so that is
    # the whole of the impermanence story here):
    #
    #   sudo install -d -m 0700 /persist/secrets
    #   printf %s '<token>' | sudo install -m 0400 /dev/stdin /persist/secrets/netskope-api-token
    #
    # The tenant is on RBAC v3, so the token comes from a Service Account under
    # Settings > Administration > Administrators & Roles with a role attached, and
    # it is shown exactly once. Keep that role at **View** on every function: the
    # role is the gate that does not depend on this server being correct, and
    # nothing we want an LLM doing here needs Manage. `/api/v2/infrastructure/
    # publishers` is the one endpoint to grant regardless — the `core` group probes
    # it to tell a bad token apart from a too-narrow role.
    apiTokenFile = "/persist/secrets/netskope-api-token";

    # Default, stated out loud because it is the one that matters: with this false
    # the delete actions are never registered, so they are absent from the schema
    # the model is shown rather than refused at call time. Netskope has no undo.
    # (`update` is not gated and can do as much damage — that is what the View-only
    # role above is for.)
    allowDestructive = false;
  };
}
