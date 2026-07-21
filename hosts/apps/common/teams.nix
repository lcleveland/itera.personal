# Microsoft Teams (unofficial Linux client). Installed per-user via itera's
# escape hatch rather than the system profile.
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [ pkgs.teams-for-linux ];
}
