# Exiled Exchange 2 (Path of Exile 2 price-check overlay). Packaged from the
# upstream AppImage and wrapped to disable the GPU and the in-game overlay.
{ pkgs, lib, ... }:
let
  version = "0.15.8";
  pname = "exiled-exchange-2";

  src = pkgs.fetchurl {
    url = "https://github.com/Kvan7/Exiled-Exchange-2/releases/download/v${version}/Exiled-Exchange-2-${version}.AppImage";
    hash = "sha256-xmEvKJkRFJokzOa/6qRqT4+QKfnfjIoAfqP+oDqyxH8=";
  };

  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

  desktopItem = pkgs.makeDesktopItem {
    name = "exiled-exchange-2";
    exec = "exiled-exchange-2";
    icon = "exiled-exchange-2";
    type = "Application";
    comment = "Path of Exile 2 overlay";
    desktopName = "Exiled Exchange 2";
  };

  exiled-exchange-2-pkg = pkgs.appimageTools.wrapType2 {
    inherit pname version src;
    extraInstallCommands = ''
      install -m 444 -D ${desktopItem}/share/applications/exiled-exchange-2.desktop \
        $out/share/applications/exiled-exchange-2.desktop
      install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/512x512/apps/exiled-exchange-2.png \
        $out/share/icons/hicolor/512x512/apps/exiled-exchange-2.png
    '';

    passthru.updateScript = pkgs.nix-update-script { };

    meta = {
      mainProgram = "exiled-exchange-2";
      description = "Path of Exile 2 overlay program";
      homepage = "https://github.com/Kvan7/Exiled-Exchange-2";
      changelog = "https://github.com/Kvan7/Exiled-Exchange-2/releases/tag/v${version}";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  itera.users.lcleveland.packages = [
    (pkgs.symlinkJoin {
      name = "exiled-exchange-2";
      paths = [ exiled-exchange-2-pkg ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/exiled-exchange-2 \
          --add-flags "--disable-gpu --no-overlay"
      '';
    })
  ];
}
