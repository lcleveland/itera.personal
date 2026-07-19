# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user.
{ pkgs, ... }:
{
  # Claude Code, both ways:
  #   - claude-code      the `claude` CLI, a terminal tool (also usable in Zed's
  #                      built-in terminal). Unfree; itera.nix.allowUnfree is on
  #                      by default.
  #   - claude-code-acp  the ACP adapter (binary `claude-agent-acp`) that plugs
  #                      Claude Code into Zed's agent panel (wired per-user below).
  #
  # NixOS note: the Zed docs/gists point agent_servers at
  # `npx @agentclientprotocol/claude-agent-acp` — DON'T. npx downloads an unpatched
  # prebuilt binary that dies on NixOS ("could not start dynamically linked
  # executable"). We point the agent straight at the Nix `claude-agent-acp` binary
  # instead, and it uses the Nix `claude-code` (autoupdater/installation-checks
  # already disabled in the nixpkgs wrapper, so it won't download a local binary).
  #
  # Auth: Zed's in-thread "Authenticate" flow is buggy (and on NixOS can trigger
  # the download above), so log in ONCE with `claude` in a terminal (`/login`);
  # that writes ~/.claude, which the ACP agent reuses — no in-app auth needed.
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.claude-code-acp
  ];

  itera = {
    # Pin the NixOS release the stateful data matches. Set ONCE at install time.
    nix.stateVersion = "25.11";

    # The `itera` command's rebuild/update verbs (and a bare `nh os switch`)
    # build from this flake. Point it at the GitHub remote so rebuilds need no
    # checkout on disk: `itera rebuild` builds the pushed revision, and being a
    # remote ref, `itera update` uses `--refresh` (fetch the newest pushed
    # revision) rather than bumping a local flake.lock. `itera.update.configuration`
    # is per-host (see hosts/*.nix) because the flake attribute (dream/framework)
    # differs from the hostname.
    update.flake = "github:lcleveland/itera.personal";

    # Both machines are AMD; a host may override.
    hardware.cpu = "amd";

    # Desktop: mango (dwl/wlroots) + DankMaterialShell. mango is opt-in.
    desktop.mango.enable = true;

    users.lcleveland = {
      description = "Lyle Cleveland";
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
        "libvirtd"
        "docker"
        "input"
      ];
      # First-boot password. Defaults to the username ("lcleveland"); CHANGE IT
      # after the first login with `passwd`. (A secrets-managed password can be
      # added later — e.g. agenix + users.users.lcleveland.hashedPasswordFile.)
      initialPassword = "lcleveland";

      # Register Claude Code in Zed's agent panel over ACP. `command` is the Nix
      # binary from claude-code-acp (installed above), NOT `npx` — see the NixOS
      # note there. Rendered by itera's Zed battery to ~/.config/zed/settings.json
      # under `agent_servers.claude`.
      programs.zed.agentServers.claude = {
        command = "claude-agent-acp";
        args = [ ];
        env = { };
      };
    };
  };
}
