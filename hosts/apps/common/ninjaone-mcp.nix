# ninjaone-mcp — an MCP server over the NinjaOne RMM public API v2, so Claude Code
# can answer questions about the tenant (devices, alerts, patching, docs, tickets,
# backups). Every host, same reasoning as netskope-mcp next door: it is a cloud
# API client that needs nothing but credentials and network.
#
# The packaging + module live in github:lcleveland/ninjaone-mcp.
{
  # Loopback HTTP on the default 127.0.0.1:8233/mcp (netskope 8231, netbox 8232).
  # Register once per host:
  #
  #   claude mcp add --scope user --transport http ninjaone http://127.0.0.1:8233/mcp
  services.ninjaone-mcp = {
    enable = true;
    region = "us2";

    # API Services (machine-to-machine) app. The ID is not secret.
    clientId = "7GZWpPHx2PIoNw_rBzbQzDjncKo";

    # Client secret, read via systemd LoadCredential. Create before the first
    # rebuild that enables this, on EVERY host:
    #
    #   printf %s '<secret>' | sudo install -m 0400 /dev/stdin /persist/secrets/ninjaone-client-secret
    clientSecretFile = "/persist/secrets/ninjaone-client-secret";

    # Full write access, deliberately — including scripts (often as SYSTEM) and
    # device admin (decommission), which the module warns about on every rebuild.
    # Every write needs the `management` scope on the API app, and the server
    # still demands a reason and, for reboot/decommission/script, a confirm.
    allowTickets = true;
    allowDocumentation = true;
    allowCustomFields = true;
    allowDeviceMaintenance = true;
    allowDeviceActions = true;
    allowScripts = true;
    allowDeviceAdmin = true;
  };
}
