# Wine's Tahoma (regular and bold), the luna style's stand-in for Tahoma (W53.2, docs/ux/styles.md §2 "Type"): Wine draws
# its own metric-compatible Tahoma (fonts/tahoma.sfd, LGPL 2.1+). Only these two faces are taken from nixpkgs'
# `winePackages.fonts`: the package also ships an "MS Sans Serif", which would win win95's chain over W95FA (W53.1).
{
  lib,
  stdenvNoCC,
  winePackages,
}:
stdenvNoCC.mkDerivation {
  pname = "wine-tahoma";
  inherit (winePackages.fonts) version;
  dontUnpack = true;
  installPhase = ''
    install -Dm444 ${winePackages.fonts}/share/fonts/truetype/tahoma.ttf $out/share/fonts/truetype/tahoma.ttf
    install -Dm444 ${winePackages.fonts}/share/fonts/truetype/tahomabd.ttf $out/share/fonts/truetype/tahomabd.ttf
  '';
  meta = {
    description = "Wine's metric-compatible Tahoma (luna style stand-in)";
    homepage = "https://www.winehq.org/";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.all;
  };
}
