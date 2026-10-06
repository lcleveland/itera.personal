# sshpass: non-interactive SSH password auth (feeds the password to ssh's prompt).
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [ pkgs.sshpass ];
}
