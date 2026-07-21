# Awakened PoE Trade (Path of Exile price-check overlay), wrapped to disable the
# GPU and the in-game overlay.
#
# The old config carried a `nixpkgs.config.permittedInsecurePackages` permit for
# electron-40.10.5; it is intentionally NOT carried over. The pinned nixpkgs now
# builds this against electron 41 (electron.meta.insecure = false), so no permit
# is needed.
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [
    (pkgs.symlinkJoin {
      name = "awakened-poe-trade";
      paths = [ pkgs.awakened-poe-trade ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/awakened-poe-trade \
          --add-flags "--disable-gpu --no-overlay"
      '';
    })
  ];
}
