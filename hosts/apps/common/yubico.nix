# YubiKey OATH GUI. itera's securityKeys battery already ships ykman, libfido2,
# the yubikey udev rules and pam_u2f, so this only adds the graphical
# authenticator plus the PC/SC daemon it needs.
{ pkgs, ... }:
{
  services.pcscd.enable = true;
  itera.users.lcleveland.packages = [ pkgs.yubioath-flutter ];
}
