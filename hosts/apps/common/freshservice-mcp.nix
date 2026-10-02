# freshservice-mcp — an MCP server over the Freshservice API v2, so Claude Code can
# answer questions about the helpdesk (tickets, assets, changes, KB, catalog).
# Every host, same reasoning as netskope-mcp and ninjaone-mcp next door: it is a
# cloud API client that needs nothing but credentials and network.
#
# The packaging + module live in github:lcleveland/freshservice-mcp.
{
  # Loopback HTTP on the default 127.0.0.1:8234/mcp (netskope 8231, netbox 8232,
  # ninjaone 8233). Register once per host:
  #
  #   claude mcp add --scope user --transport http freshservice http://127.0.0.1:8234/mcp
  services.freshservice-mcp = {
    enable = true;
    domain = "lselectric.freshservice.com";

    # API key of the agent the server acts as, read via systemd LoadCredential.
    # Create before the first rebuild that enables this, on EVERY host:
    #
    #   printf %s '<key>' | sudo install -m 0400 /dev/stdin /persist/secrets/freshservice-api-key
    apiKeyFile = "/persist/secrets/freshservice-api-key";

    # Full write access, deliberately — including ticket replies (emails
    # requesters and third parties), approvals (as the API key's agent) and ops
    # (public status pages, on-call), which the module warns about on every
    # rebuild. All tool groups are already on by default.
    allowTickets = true;
    allowTicketReplies = true;
    allowItil = true;
    allowAssets = true;
    allowKnowledge = true;
    allowProjects = true;
    allowPeople = true;
    allowApprovals = true;
    allowOps = true;
    allowCustomObjects = true;
  };
}
