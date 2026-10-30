# W95FA (Alina Sava, FontsArena, 2019): a free outline re-drawing of the 9x UI bitmap face, the win95 style's stand-in for
# MS Sans Serif (W53.1, docs/ux/styles.md §1 "Type"). SIL Open Font License 1.1 (OFL.txt in the archive;
# https://fontsarena.com/w95fa-by-alina-sava/). Its outlines sit on an 80-unit grid of a 1000-unit em: one pixel per 80
# units, so 12–13 px with full hinting draws the bitmap's 9 px capitals crisply. nixpkgs does not package it.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation {
  pname = "w95fa";
  version = "2019-12-28";
  src = fetchzip {
    url = "https://fontsarena.com/wp-content/uploads/2020/01/W95FA.zip";
    stripRoot = false;
    sha256 = "0dlbm0ncckblji4vj2jgyqlcy555sy20m5b38jg4xlgj3gwfg1ks";
  };
  installPhase = ''
    install -Dm444 W95FA/W95FA.otf $out/share/fonts/opentype/W95FA.otf
    install -Dm444 W95FA/OFL.txt $out/share/licenses/w95fa/OFL.txt
  '';
  meta = {
    description = "Free re-drawing of the Windows 9x UI bitmap font (win95 style stand-in)";
    homepage = "https://fontsarena.com/w95fa-by-alina-sava/";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
