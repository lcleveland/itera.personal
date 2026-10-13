# microsoft-directory-mcp — an MCP server over the on-prem Active Directory forest
# (LDAPS) and the Entra ID tenant (Graph), so Claude Code can read and edit users,
# groups, devices and policy on both sides. Work-tenant hosts only (framework,
# x1yoga): the domain controllers are only reachable on the work network, so the
# flake module comes in through specialArgs (see flake.nix), same as netbox-mcp.
#
# The packaging + module live in github:lcleveland/microsoft-directory-mcp.
{ microsoft-directory-mcp, ... }:
{
  imports = [ microsoft-directory-mcp.nixosModules.default ];

  # Loopback HTTP on 8236: the default 8235 is falcon-mcp's (netskope 8231,
  # netbox 8232, ninjaone 8233, freshservice 8234). Register once per host:
  #
  #   claude mcp add --scope user --transport http directory http://127.0.0.1:8236/mcp
  #
  # Secrets, read via systemd LoadCredential. Create before the first rebuild, on
  # each work host:
  #
  #   printf %s '<password>' | sudo install -m 0400 /dev/stdin /persist/secrets/msdir-ad-bind-password
  #   sudo install -m 0400 entra-cert.pem /persist/secrets/msdir-entra-cert.pem  # RSA key + cert, one PEM
  services.microsoft-directory-mcp = {
    enable = true;
    http.addr = "127.0.0.1:8236";

    ad = {
      forest = "lselectric.local"; # TODO: confirm forest root DNS name
      bindUser = "svc-directory-mcp@lselectric.local"; # UPN suffix follows the forest guess above
      bindPasswordFile = "/persist/secrets/msdir-ad-bind-password";
    };

    entra = {
      tenant = "4897871c-030f-4bb7-bef7-4c527bdb7dce";
      clientId = "1ee53779-7c94-48b2-a9bd-b7e75dcbd1ab"; # app: microsoft-directory-mcp
      certFile = "/persist/secrets/msdir-entra-cert.pem";
    };

    # Full write access, deliberately — including password resets, deletes and
    # Intune retire/wipe. Protected targets (tier-0 AD, Entra role holders) are
    # refused in code regardless; the bind account's AD rights and the app
    # registration's Graph permissions are the real limit, scope them there.
    capabilities = [
      "ad-account-state"
      "ad-passwords"
      "ad-group-membership"
      "ad-objects"
      "ad-delete"
      "ad-gpo-links"
      "ad-password-policy"
      "entra-account-state"
      "entra-credentials"
      "entra-group-membership"
      "entra-objects"
      "entra-delete"
      "entra-licenses"
      "entra-devices"
      "entra-risk"
      "intune-device-actions"
      "intune-retire-wipe"
    ];
  };
}
