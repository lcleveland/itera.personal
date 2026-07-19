# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user.
{ pkgs, ... }:
{
  # Claude Code's ACP server binary, so Zed's agent panel can spawn it (wired
  # per-user below via itera.users.lcleveland.programs.zed.agentServers). The
  # nixpkgs `claude-code-acp` package installs it as `claude-agent-acp`.
  environment.systemPackages = [ pkgs.claude-code-acp ];

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

      # Plug Claude Code into Zed's agent panel over ACP. The nixpkgs
      # `claude-code-acp` package (installed above) provides the binary as
      # `claude-agent-acp`. Auth is Claude Code's own subscription login, done
      # once inside Zed — no API key lives in this config. Rendered by itera's
      # Zed battery to `~/.config/zed/settings.json` under `agent_servers.claude`.
      programs.zed.agentServers.claude = {
        command = "claude-agent-acp";
        args = [ ];
        env = { };
      };
    };
  };
}
