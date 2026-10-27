# network-mcp — an MCP server that reads network devices over SSH (and SNMP), so
# Claude Code can run gated `show` commands, read configs and make gated config
# changes on the work routers and switches. Work-tenant hosts only (framework, x1yoga): the devices are only
# reachable on the work network, so this file is imported only through work.nix's
# apps, same as netbox-mcp.
#
# The packaging + module live in github:lcleveland/network-mcp.
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.network-mcp.nixosModules.default ];

  # Loopback HTTP on 8237: the default 8232 is netbox-mcp's. Register once per host:
  #
  #   claude mcp add --scope user --transport http network http://127.0.0.1:8237/mcp
  #
  # Secrets, read via systemd LoadCredential, each a JSON file. Create before the
  # first rebuild, on each work host:
  #
  #   printf %s '{"username":"<user>","password":"<pw>"}' | sudo install -m 0400 /dev/stdin /persist/secrets/network-mcp-ssh-read
  #   printf %s '{"username":"<user>","password":"<pw>"}' | sudo install -m 0400 /dev/stdin /persist/secrets/network-mcp-ssh-write
  #   printf %s '{"management_prefixes":["<cidr>", ...]}' | sudo install -m 0400 /dev/stdin /persist/secrets/network-mcp-prefixes
  #
  # Device SSH host keys, pinned by IP (no trust-on-first-use). Not secret, but the
  # unit runs as a DynamicUser, so the file must be world-readable:
  #
  #   ssh-keyscan <device ip> ... | sudo install -D -m 0444 /dev/stdin /persist/network-mcp/known_hosts
  services.network-mcp = {
    enable = true;
    port = 8237;
    knownHostsFile = "/persist/network-mcp/known_hosts";

    credentials = {
      ssh-read = "/persist/secrets/network-mcp-ssh-read";
      # Must land at a privileged (#) prompt: the server never runs `enable`.
      ssh-write = "/persist/secrets/network-mcp-ssh-write";
      netbox-token = "/run/network-mcp-netbox-token"; # wrapped from netbox-mcp's, below
      prefixes = "/persist/secrets/network-mcp-prefixes";
    };

    # Config writes via network_change (IOS-XE / NX-OS only): plan, apply under a
    # revert timer, confirm or roll back. Unvalidated on hardware upstream, so
    # trial it on a non-critical device first; IOS-XE needs `archive path` set on
    # the device before apply. allowSave adds action=save (copy running-config
    # startup-config), only at the running config of the last confirmed change.
    allowConfig = true;
    allowSave = true;
    settings = {
      # Lets `network_change action=archive` set `archive path` once on an IOS-XE
      # device that lacks it (unsaved, not reverted). Key is the NetBox platform slug.
      platforms.cisco-ios-xe.archive_path = "flash:archive";
      # The server dials nothing outside the management prefixes. They come from
      # NetBox IPAM (management_prefixes below); this credential ref is only the
      # fallback when NetBox is unreachable at startup, and keeps the site
      # addressing out of the Nix store. Both are read once at startup.
      prefixes_ref = "prefixes";
      # Devices come from NetBox; only those tagged `network-mcp` are opted in.
      sources = [
        {
          name = "netbox";
          type = "netbox";
          url = "http://netbox.lselectric.local";
          token_ref = "netbox-token";
          opt_in_tag = "network-mcp";
          # oob_ip first: a router whose primary IP (loopback) is unroutable from
          # here carries its reachable management address there.
          address_order = [
            "oob_ip"
            "primary_ip4"
            "primary_ip6"
          ];
          # IPAM prefixes tagged network-mcp-mgmt are the management prefixes;
          # anyone who can tag a prefix in NetBox widens where the server connects.
          management_prefixes.tag = "network-mcp-mgmt";
        }
      ];
      rules = [
        {
          match = "default";
          read_ref = "ssh-read";
          write_ref = "ssh-write";
        }
      ];
    };
  };

  # network-mcp wants the token as JSON {"token": …}; netbox-mcp's file is the
  # bare token. Wrap it on every network-mcp start, so there is one token to rotate.
  systemd.services.network-mcp-netbox-token = {
    description = "Wrap netbox-mcp's API token for network-mcp";
    before = [ "network-mcp.service" ];
    requiredBy = [ "network-mcp.service" ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      ${pkgs.jq}/bin/jq -n --rawfile t ${config.services.netbox-mcp.apiTokenFile} \
        '{token: ($t | rtrimstr("\n"))}' > /run/network-mcp-netbox-token
    '';
  };
}
