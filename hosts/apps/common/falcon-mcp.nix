# falcon-mcp — an MCP server over the CrowdStrike Falcon API, so Claude Code can
# answer questions about the tenant (alerts, hosts, policy, intel, NG-SIEM).
# Every host, same reasoning as netskope-mcp next door: it is a cloud API client
# that needs nothing but credentials and network. Unrelated to
# apps/work/falcon-sensor.nix despite the name — that is the endpoint agent.
#
# The packaging + module live in github:lcleveland/falcon-mcp.
{
  # Loopback HTTP on the default 127.0.0.1:8235/mcp (netskope 8231, netbox 8232,
  # ninjaone 8233, freshservice 8234). Register once per host:
  #
  #   claude mcp add --scope user --transport http falcon http://127.0.0.1:8235/mcp
  services.falcon-mcp = {
    enable = true;
    http.enable = true;

    # Its OWN API client, not the sensor-download one in apps/work/falcon-sensor.nix
    # (that client is meant to carry the installer scope and nothing else). Read via
    # systemd LoadCredential. Create before the first rebuild, on EVERY host:
    #
    #   printf %s '<client id>'     | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-mcp-client-id
    #   printf %s '<client secret>' | sudo install -m 0400 /dev/stdin /persist/secrets/falcon-mcp-client-secret
    #
    # cloud is left unset, so the region is autodiscovered.
    clientIdFile = "/persist/secrets/falcon-mcp-client-id";
    clientSecretFile = "/persist/secrets/falcon-mcp-client-secret";

    # Full write access, deliberately — including containment and RTR on live
    # hosts, rtr-respond (kill processes, put/delete files) and destructive (hide
    # hosts, delete quarantined files), the last two of which the module warns
    # about on every rebuild. The API client's scopes are the gate that does not
    # depend on this server being correct. All are off upstream by default.
    allow = {
      triage = true;
      host-tags = true;
      containment = true;
      detection-add = true;
      detection-remove = true;
      fleet-config = true;
      rtr-read = true;
      rtr-respond = true;
      destructive = true;
      workflows = true;
    };
  };
}
