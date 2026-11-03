# ONLYOFFICE desktop editors (Office document suite).
#
# It still links gtk2, which nixpkgs marks broken ahead of its removal
# (NixOS/nixpkgs#410814). Downgrade that to a warning; drop this once
# onlyoffice-desktopeditors moves to gtk3, or before NixOS 27.05.
{ pkgs, ... }:
{
  nixpkgs.config.problems.handlers."gtk+".broken = "warn";

  itera.users.lcleveland.packages = [ pkgs.onlyoffice-desktopeditors ];
}
