# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user.
{ ... }:
{
  # Apps shared by both hosts, migrated from the old eiros.users.{personal,work}
  # repos. One module per app under ./apps/common.
  imports = [
    ./apps/common/teams.nix
    ./apps/common/zoom.nix
    ./apps/common/yubico.nix
    ./apps/common/onlyoffice.nix
    ./apps/common/bruno.nix
    ./apps/common/caido.nix
    ./apps/common/obs.nix
  ];

  # Claude Code, both ways — all from itera's `itera.ai.claude.enable` battery
  # (set below), so nothing is installed by hand here:
  #   - claude-code      the `claude` CLI, a terminal tool (also usable in Zed's
  #                      built-in terminal). Ships `pkgs.claude-code` system-wide
  #                      AND, under itera's default-on impermanence, persists the
  #                      per-user state (~/.claude, ~/.claude.json) so the login
  #                      survives the wiped root. Unfree; itera.nix.allowUnfree is
  #                      on by default.
  #   - claude-agent-acp the ACP adapter that plugs Claude Code into Zed's agent
  #                      panel. `itera.ai.claude.acp.enable` defaults to
  #                      `itera.ai.claude.enable`, so enabling the CLI brings the
  #                      adapter too; with the editor battery on (default) itera
  #                      auto-registers it under Zed's `agent_servers` — no manual
  #                      package or per-user `agentServers` block needed.
  #
  # NixOS note: the Zed docs/gists point agent_servers at
  # `npx @agentclientprotocol/claude-agent-acp` — DON'T. npx downloads an unpatched
  # prebuilt binary that dies on NixOS. itera's battery instead points Zed at the
  # Nix `claude-agent-acp` binary, which uses the Nix `claude-code`.
  #
  # Auth: Zed's in-thread "Authenticate" flow is buggy (and on NixOS can trigger
  # the download above), so log in ONCE with `claude` in a terminal (`/login`);
  # that writes ~/.claude, which the ACP agent reuses — no in-app auth needed.

  # Git identity for lcleveland. No upstream itera battery for this yet, so write
  # ~/.gitconfig directly through the user's hjem home (re-linked every boot, so
  # it needs no impermanence persistence).
  hjem.users.lcleveland.files.".gitconfig".text = ''
    [user]
    	name = Lyle Cleveland
    	email = lyle.cleveland@proton.me
  '';

  # NinjaOne remote session player: installs `ncplayer` (FHS-wrapped RPM) and
  # registers it as the ninjarmm:// URL handler. Module comes from the
  # ninjarmm-ncplayer flake input, imported for every host in flake.nix.
  programs.ninjarmm-ncplayer.enable = true;

  itera = {
    # Claude Code CLI, system-wide + state persisted across the wiped root.
    ai.claude.enable = true;

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

      # Claude Code is registered in Zed's agent panel automatically by itera's
      # ACP battery (see the Claude note at the top of this file) — no per-user
      # `programs.zed.agentServers.claude` block is needed.
    };
  };
}
