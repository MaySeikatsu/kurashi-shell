# Selawik (Microsoft, 2015): an open-source face "metrically compatible with Segoe UI" (Microsoft Learn, typography), the
# aero style's stand-in for Segoe UI (W53.2, docs/ux/styles.md §3 "Type"). SIL Open Font License 1.1 (the repository's
# LICENSE.txt; https://github.com/microsoft/Selawik). nixpkgs does not package it.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation {
  pname = "selawik";
  version = "1.01";
  src = fetchzip {
    url = "https://github.com/microsoft/Selawik/releases/download/1.01/Selawik_Release.zip";
    stripRoot = false;
    sha256 = "0178ipd9iiq5m40awx9cx7j915r1k5y1k9y3jijb8pn5q4kxgf05";
  };
  installPhase = ''
    for f in selawk.ttf selawkb.ttf selawkl.ttf selawksb.ttf selawksl.ttf; do
      install -Dm444 "$f" "$out/share/fonts/truetype/$f"
    done
  '';
  meta = {
    description = "Open-source face metrically compatible with Segoe UI (aero style stand-in)";
    homepage = "https://github.com/microsoft/Selawik";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
