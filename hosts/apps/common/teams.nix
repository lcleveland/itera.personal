# Microsoft Teams (unofficial Linux client). Installed per-user via itera's
# escape hatch rather than the system profile.
#
# YubiKey / FIDO2 sign-in (upstream's "Security Key and WebAuthn Support" beta,
# ADR 021, issues #802/#2357): Electron/Chromium on Linux ship no native FIDO2
# authenticator backend, so a hardware-key login otherwise spins forever or never
# shows the PIN dialog. teams-for-linux 2.14+ works around this with its own
# backend that shells out to libfido2's CLI tools, gated behind an opt-in config
# flag. Three pieces are needed, and itera's securityKeys battery (on by default)
# already provides the first two:
#
#   1. Device access — libfido2's 70-u2f.rules, whose every rule carries
#      TAG+="uaccess", so the seat-local user gets the hidraw node with no group
#      membership. That is upstream's "add yourself to plugdev" step, done better.
#   2. The CLI tools — app/webauthn/fido2Backend.js spawns `fido2-token`,
#      `fido2-cred` and `fido2-assert` by bare name off PATH (probing with
#      `which`), which is upstream's `fido2-tools` package. On NixOS those live in
#      pkgs.libfido2, which the battery now installs system-wide alongside `ykman`.
#      (`which` itself is in NixOS's own requiredPackages, so it is always there.)
#   3. The opt-in flag — the only Teams-specific piece, set below.
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [ pkgs.teams-for-linux ];

  # Turn the WebAuthn backend on. teams-for-linux reads /etc/teams-for-linux/config.json
  # first and then ~/.config/teams-for-linux/config.json, so the system file is the
  # declarative surface — and the right one here, because the app's own
  # electron-store ("legacy config store") writes to that *user* path, which a
  # read-only Nix symlink would break. Note the two files are merged with a shallow
  # spread (`{...system, ...user}`): if a user config.json ever appears with its own
  # top-level `auth` key it replaces this whole block, not just the keys it sets.
  #
  # Add `"debug": true` beside `enabled` (plus logConfig.transports.file.level =
  # "debug") to trace a failing key, then watch:
  #   tail -F ~/.config/teams-for-linux/logs/main.log | grep -i webauthn
  environment.etc."teams-for-linux/config.json".text = builtins.toJSON {
    auth.webauthn.enabled = true;
  };
}
