# tuios: terminal UI window manager (tiling/floating terminal sessions in one TTY).
#
# WezTerm (itera's terminal battery) opens straight into tuios: `tuios attach`
# reattaches the most recent session (starting the daemon and restoring saved
# sessions if needed), or opens a new one when there is none. A plain shell
# is still `wezterm start -- nu`.
#
# tuios settings go in config.d/, not config.toml: tuios rewrites config.toml
# from its settings page, and config.d files are merged under it (config.toml
# wins, so a key here must not also be set there).
#
# `programs.tuios.enable` (default on) gates the whole module. When it and
# Claude Code (`itera.ai.claude.enable`) are both on, a login-time user service
# runs `tuios integration install claude-code --statusline`: it merges tuios's agent-state
# hooks and status line into ~/.claude/settings.json and writes the tuios skill;
# Claude's permission prompts that fit on one line are then held for the tuios
# Inbox (`[agents.approvals]`). The install can't be an
# hjem file, since Claude Code rewrites settings.json itself; reinstalling an
# integration that is already current changes nothing.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.tuios;
in
{
  options.programs.tuios.enable = lib.mkEnableOption "tuios" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.tuios-claude-integration = lib.mkIf config.itera.ai.claude.enable {
      description = "Install tuios hooks, status line and skill into Claude Code";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "lcleveland";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.tuios} integration install claude-code --statusline";
      };
    };

    hjem.users.lcleveland.xdg.config.files."tuios/config.d/nixos.toml".source =
      (pkgs.formats.toml { }).generate "tuios-nixos.toml"
        (
          {
            startup = {
              open_default_window = true; # an empty session starts with a terminal
              start_in_terminal_mode = true; # typing goes to the pane, not window mode
            };
            # Agent alerts as desktop popups that time out. tuios's own popup goes via
            # WezTerm, which sends it critical with timeout 0, so DMS keeps it up forever.
            # The daemon runs `command` with sh and TUIOS_* in the env; it reads it at start.
            notifications.agent = {
              notify = false;
              command = ''${lib.getExe pkgs.libnotify} -a tuios -u normal -t 8000 "$TUIOS_WINDOW_NAME: $TUIOS_AGENT_STATE" "$TUIOS_AGENT_MESSAGE"'';
            };
          }
          // lib.optionalAttrs config.itera.ai.claude.enable {
            # Answer short Claude permission prompts from the Inbox (prefix+i): 1 once, 2 always, 3 deny.
            agents.approvals = {
              enabled = [ "claude-code" ];
              hold_seconds = 120;
            };
          }
        );

    itera.users.lcleveland = {
      packages = [ pkgs.tuios ];
      programs.wezterm.settings = {
        default_prog = [
          (lib.getExe pkgs.tuios)
          "attach"
        ];
        # tuios reads key releases and unambiguous modifiers through the kitty
        # keyboard protocol (hold_window_mode needs it); WezTerm ships it off.
        enable_kitty_keyboard = true;
        # tuios draws its own tabs/workspaces; WezTerm's bar only shows with 2+ tabs.
        hide_tab_bar_if_only_one_tab = true;
      };
    };
  };
}
