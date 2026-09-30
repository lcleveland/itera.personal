# netbox-mcp — an MCP server over the NetBox REST API (IPAM/DCIM), so Claude Code
# can read and edit the work NetBox at netbox.lselectric.local. Work-tenant
# hosts only (framework, x1yoga): that NetBox is only reachable on the work
# network, so the flake module comes in through specialArgs (see flake.nix)
# rather than the every-host `modules` list netskope-mcp uses.
#
# The packaging + module live in github:lcleveland/netbox-mcp.
{ netbox-mcp, ... }:
{
  imports = [ netbox-mcp.nixosModules.default ];

  # Loopback HTTP, same shape as netskope-mcp (apps/common/netskope-mcp.nix), but
  # on 8232: 8231 is BOTH servers' default and netskope-mcp already holds it.
  # Register once per host:
  #
  #   claude mcp add --scope user --transport http netbox http://127.0.0.1:8232/mcp
  services.netbox-mcp = {
    enable = true;
    port = 8232;
    url = "http://netbox.lselectric.local";

    # NetBox v2 API token (`nbt_<key>.<token>`), read via systemd LoadCredential.
    # Create before the first rebuild that enables this, on each work host:
    #
    #   printf %s '<token>' | sudo install -m 0400 /dev/stdin /persist/secrets/netbox-api-token
    apiTokenFile = "/persist/secrets/netbox-api-token";

    # Full write access, deliberately — including delete, which NetBox cannot
    # undo (the module warns about it on every rebuild). The token's NetBox
    # permissions are the real limit; scope them there.
    allowCreate = true;
    allowUpdate = true;
    allowDelete = true;
  };
}
