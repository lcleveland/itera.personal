# Bruno API client (GUI + CLI).
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [
    pkgs.bruno
    pkgs.bruno-cli
  ];
}
