# Stability Matrix (Stable Diffusion package manager / inference UI). Packaged
# from the upstream Linux zip that wraps a single AppImage.
{ pkgs, lib, ... }:
let
  pname = "stability-matrix";
  version = "2.16.1";

  zip = pkgs.fetchurl {
    url = "https://github.com/LykosAI/StabilityMatrix/releases/download/v${version}/StabilityMatrix-linux-x64.zip";
    hash = "sha256-A+FT+cMGguOPviAtokeiUc/+g9UdUpHyoiMp0+pjuQo=";
  };

  # The Linux release is a zip wrapping a single AppImage; appimageTools needs the
  # AppImage file directly, so unwrap it.
  src =
    pkgs.runCommand "StabilityMatrix-${version}.AppImage"
      {
        nativeBuildInputs = [ pkgs.unzip ];
      }
      ''
        unzip ${zip} StabilityMatrix.AppImage -d .
        install -m444 StabilityMatrix.AppImage $out
      '';

  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

  stability-matrix-pkg = pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    # Extra runtime libs the bundled .NET/Avalonia app and its child processes expect.
    extraPkgs =
      pkgs: with pkgs; [
        icu
        openssl
        fontconfig
        # The portable Python 3.10 StabilityMatrix downloads links against
        # libcrypt.so.1, which only libxcrypt-legacy provides.
        libxcrypt-legacy
      ];

    extraInstallCommands = ''
      install -m444 -D ${appimageContents}/zone.lykos.stabilitymatrix.desktop \
        $out/share/applications/zone.lykos.stabilitymatrix.desktop
      install -m444 -D ${appimageContents}/usr/share/icons/hicolor/512x512/apps/zone.lykos.stabilitymatrix.png \
        $out/share/icons/hicolor/512x512/apps/zone.lykos.stabilitymatrix.png
      substituteInPlace $out/share/applications/zone.lykos.stabilitymatrix.desktop \
        --replace-warn "Exec=/usr/bin/StabilityMatrix.Avalonia" "Exec=stability-matrix"
    '';

    meta = {
      mainProgram = "stability-matrix";
      description = "Multi-platform package manager and inference UI for Stable Diffusion";
      homepage = "https://github.com/LykosAI/StabilityMatrix";
      changelog = "https://github.com/LykosAI/StabilityMatrix/releases/tag/v${version}";
      license = lib.licenses.agpl3Only;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  itera.users.lcleveland.packages = [ stability-matrix-pkg ];
}
