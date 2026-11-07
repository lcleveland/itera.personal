# tuios: terminal UI window manager (tiling/floating terminal sessions in one TTY).
#
# WezTerm (itera's terminal battery) opens straight into tuios: `tuios attach`
# reattaches the most recent session (starting the daemon and restoring saved
# sessions if needed), or opens a new one when there is none. A plain shell
# is still `wezterm start -- nu`.
{ lib, pkgs, ... }:
{
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
}
