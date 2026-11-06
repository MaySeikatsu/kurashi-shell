# The handwriting fonts the font mix's preset names beside Kalam (I176, K93; docs/ux/fonts.md): Patrick Hand, Handlee, Gochi Hand. SIL Open
# Font License 1.1, from google/fonts at a fixed commit; nixpkgs packages them only inside its whole google-fonts.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  rev = "38411257417e616c5d4daa1b9e91a3dbcebe1c2e";
  font = path: hash: fetchurl {
    url = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/${path}";
    inherit hash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "kurashi-handwriting-fonts";
  version = "1";
  dontUnpack = true;
  installPhase = ''
    install -Dm444 ${font "patrickhand/PatrickHand-Regular.ttf" "sha256-Dxc7Pmy20a8lur9/AFfFrE7hH5mSsEabuBfpZ+9K0Pw="} $out/share/fonts/truetype/PatrickHand-Regular.ttf
    install -Dm444 ${font "handlee/Handlee-Regular.ttf" "sha256-e5nA8pG11S4GxmSYodDdbf9Foy4y0TvgicYNLY3ABEU="} $out/share/fonts/truetype/Handlee-Regular.ttf
    install -Dm444 ${font "gochihand/GochiHand-Regular.ttf" "sha256-xGsCmrSEayk14wGvCyz4Wh100oWOajNjaj5kzzzEaWs="} $out/share/fonts/truetype/GochiHand-Regular.ttf
  '';
  meta = {
    description = "Handwriting fonts for the font mix preset";
    homepage = "https://github.com/google/fonts";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
