# Microsoft Teams (unofficial Linux client). Installed per-user via itera's
# escape hatch rather than the system profile.
#
# YubiKey / FIDO2 sign-in (upstream's "Security Key and WebAuthn Support" beta,
# ADR 021, issues #802/#2357): Electron/Chromium on Linux ship no native FIDO2
# authenticator backend, so a hardware-key login otherwise spins forever or never
# shows the PIN dialog. teams-for-linux 2.14+ works around this with its own
# backend that shells out to libfido2's CLI tools, gated behind an opt-in config
# flag. Three pieces are needed, two of which we add here:
#
#   1. Device access — already covered by itera's securityKeys battery (on by
#      default), which installs libfido2's 70-u2f.rules. Every rule carries
#      TAG+="uaccess", so the seat-local user gets the hidraw node with no group
#      membership; that is upstream's "add yourself to plugdev" step, done better.
#   2. The CLI tools — app/webauthn/fido2Backend.js spawns `fido2-token`,
#      `fido2-cred` and `fido2-assert` by bare name off PATH (via `which`), which
#      is upstream's `fido2-tools` package. On NixOS those live in pkgs.libfido2,
#      and the securityKeys battery only uses that package for its udev rules —
#      it never puts the binaries on PATH. Rather than leak them into the system
#      profile, wrap the app so it carries its own PATH prefix; that also makes
#      key support independent of however the desktop entry got launched.
#   3. The opt-in flag — see the /etc config below.
{ pkgs, ... }:
let
  # Same app, plus libfido2's fido2-* tools on its PATH. symlinkJoin (rather than
  # overrideAttrs + postFixup) keeps the cached binary build: it only re-links the
  # outputs and wraps the launcher, no Electron/npm rebuild. `which` is pulled in
  # too because fido2Backend.js probes for the tools with it, so a session PATH
  # without it would make the backend report "no tools installed".
  teams-for-linux = pkgs.symlinkJoin {
    name = "teams-for-linux-fido2-${pkgs.teams-for-linux.version}";
    paths = [ pkgs.teams-for-linux ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/teams-for-linux \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.libfido2
            pkgs.which
          ]
        }
    '';
    # The .desktop entry is `Exec=teams-for-linux %U` (bare name, resolved off
    # PATH), so the launcher, the msteams:// URL handler and the tray all land on
    # the wrapper without patching the entry.
    inherit (pkgs.teams-for-linux) meta;
  };
in
{
  itera.users.lcleveland.packages = [ teams-for-linux ];

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
