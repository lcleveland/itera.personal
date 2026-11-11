# Google Chrome, alongside itera's Vivaldi (which stays the default browser), for
# Claude in Chrome: the Claude browser extension officially supports only Chrome
# and Edge. Claude Code writes the extension's native-messaging manifest into
# ~/.config/google-chrome itself on `claude --chrome` / `/chrome`, and /home is
# persisted, so nothing else is wired here. NIXOS_OZONE_WL is already set, which
# the nixpkgs google-chrome wrapper reads to run natively on Wayland.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.google-chrome ];
}
