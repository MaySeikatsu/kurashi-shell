# Misaki (美咲フォント, 2021-05-05 TTF edition) by Num Kadoma (門真 なむ), https://littlelimit.net/misaki.htm: 8×8-dot Japanese
# pixel fonts drawn as outlines with embedded bitmaps. Three faces: MisakiGothic (misaki_gothic.ttf), MisakiGothic2nd
# (misaki_gothic_2nd.ttf) and MisakiMincho (misaki_mincho.ttf). The snes and ps2 styles' 8×8 Japanese face (W53.5,
# docs/ux/styles.md "Fonts"). nixpkgs (nixos-unstable, `nix eval nixpkgs#misaki`, W53.5) does not package it.
#
# Licence, as the site states it (https://littlelimit.net/font.htm, the ライセンス section; the archive's misaki.txt says
# the same in other words):
#   "These fonts are free software. Unlimited permission is granted to use, copy, and distribute them, with or without
#    modification, either commercially or noncommercially. THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY."
# The archive has no separate licence file, so misaki.txt (manual, licence and the Copyright(C) 2002-2021 Num Kadoma
# line) is installed as the licence document beside the fonts.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation {
  pname = "misaki";
  version = "2021-05-05";
  src = fetchzip {
    url = "https://littlelimit.net/arc/misaki/misaki_ttf_2021-05-05.zip";
    stripRoot = false;
    sha256 = "0rj5k41vdbp2if6m0v1wd33n5pgfswdnrk34n5dfpap7vg4mwkkw";
  };
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts/truetype $out/share/licenses/misaki
    install -m444 misaki_gothic.ttf misaki_gothic_2nd.ttf misaki_mincho.ttf $out/share/fonts/truetype/
    install -m444 misaki.txt $out/share/licenses/misaki/misaki.txt
    runHook postInstall
  '';
  meta = {
    description = "Misaki: 8x8-dot Japanese pixel fonts (gothic, gothic 2nd, mincho) by Num Kadoma, free to use and redistribute";
    homepage = "https://littlelimit.net/misaki.htm";
    license = lib.licenses.free;
    platforms = lib.platforms.all;
  };
}
