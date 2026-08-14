# Out-of-tree mt76 with MediaTek MT7927 (MT6639 "Filogic 380") Wi-Fi 7 support.
#
# The in-tree mt7925e in kernel 7.1.8 claims only 14c3:0717 and 14c3:7925 —
# nothing in the kernel claims 14c3:7927 — so dream's onboard Wi-Fi never binds
# a driver and there is no wlan interface at all. This rebuilds the kernel's own
# mt76 tree with the MT7927 patch set from jetm/mediatek-mt7927-dkms, which adds
# the chip IDs, MT7927 firmware paths, its different DMA ring layout and IRQ
# map, 320 MHz EHT, and disables ASPM (which otherwise collapses throughput).
#
# Only the Wi-Fi half is built. The DKMS package also ships out-of-tree
# btusb/btmtk, but kernel 7.1.8 already has full in-tree MT6639 Bluetooth — see
# hosts/dream.nix, which supplies the one missing piece, the BT firmware blob.
# Rebuilding btusb here would needlessly risk the working USB Bluetooth dongle.
#
# The Wi-Fi firmware itself needs nothing extra: linux-firmware already ships
# WIFI_RAM_CODE_MT6639_2_1.bin and WIFI_MT6639_PATCH_MCU_2_1_hdr.bin.
#
# MAINTENANCE: this is an out-of-tree backport pinned to one upstream tag. On
# every kernel bump, re-check it — the patch loop below fails the build loudly
# if a patch neither applies nor is already present, so a silent half-patched
# driver is not possible. Drop this file entirely once MT7927 support lands in
# mainline mt76.
{ lib, stdenv, fetchzip, kernel }:

let
  dkms = fetchzip {
    url = "https://github.com/jetm/mediatek-mt7927-dkms/archive/refs/tags/v2.13-1.tar.gz";
    hash = "sha256-GXbwhZbvfWE+w9TgMReAsAFL/WkbCokzEiIChmX2d00=";
  };
in
stdenv.mkDerivation {
  pname = "mt7927-mt76";
  version = "2.13-1-${kernel.version}";

  src = kernel.src;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Only the mt76 tree; kernel 7.1.8 already has MT6639 Bluetooth in-tree, so
  # the DKMS package's out-of-tree btusb/btmtk are deliberately NOT built.
  unpackPhase = ''
    runHook preUnpack
    tar -xf $src --strip-components=6 \
      linux-${kernel.version}/drivers/net/wireless/mediatek/mt76
    runHook postUnpack
  '';

  patchPhase = ''
    runHook prePatch
    # Some of these patches have already landed upstream in this kernel. Apply
    # what is missing, skip what is present, and fail loudly on a real conflict
    # rather than silently building a half-patched driver.
    for p in ${dkms}/mt7927-wifi-*.patch; do
      n=$(basename "$p")
      if patch -p1 --forward --fuzz=0 --dry-run -s <"$p" >/dev/null 2>&1; then
        echo "apply   $n"
        patch -p1 --forward --fuzz=0 -s <"$p"
      elif patch -p1 --reverse --fuzz=0 --dry-run -s <"$p" >/dev/null 2>&1; then
        echo "skip    $n (already upstream)"
      else
        echo "ERROR: $n neither applies nor is already present" >&2
        exit 1
      fi
    done
    cp ${dkms}/mt76.Kbuild Kbuild
    cp ${dkms}/mt7921.Kbuild mt7921/Kbuild
    cp ${dkms}/mt7925.Kbuild mt7925/Kbuild
    runHook postPatch
  '';

  makeFlags = [
    "-C" "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
    "modules"
  ];

  # depmod prefers updates/ over kernel/, so these override the in-tree mt76.
  installPhase = ''
    runHook preInstall
    d=$out/lib/modules/${kernel.modDirVersion}/updates
    mkdir -p $d
    find . -name '*.ko' -exec install -Dm444 {} $d/ \;
    echo "installed:"; ls $d
    runHook postInstall
  '';

  meta = {
    description = "Out-of-tree mt76 with MediaTek MT7927 (Filogic 380) Wi-Fi 7 support";
    license = lib.licenses.gpl2Only;
  };
}
