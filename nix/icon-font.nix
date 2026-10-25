# The shell's icon font, subset at build time (W39-block, I194): "Kurashi Symbols Rounded" and "Kurashi Symbols Sharp",
# Material Symbols cut down to the ligatures in ./icon-names.txt with every axis kept (nix/icon-subset.py). ~0.7 / 1.2 MB
# instead of 8.9 / 15.2 MB, so the shell's resident icon font shrinks by the same. nix/package.nix installs the two files,
# the Home-Manager and NixOS font defaults list this derivation, and kurashi-theme prefers the families (font.icons, W41
# rows 445–446); a name the subset lacks falls back to the full Material Symbols family (Icon.qml).
#   nix build --impure --expr 'let f = builtins.getFlake (toString ./.); p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
#                              in p.callPackage ./nix/icon-font.nix { }'
{
  lib,
  runCommand,
  python3,
  material-symbols,
}:
let
  py = python3.withPackages (ps: [ ps.fonttools ]);
in
runCommand "kurashi-icon-font"
  {
    nativeBuildInputs = [ py ];
    names = ./icon-names.txt;
    script = ./icon-subset.py;
    meta = {
      description = "Material Symbols Rounded and Sharp subset to the icons kurashi-shell draws";
      license = lib.licenses.asl20;
      platforms = lib.platforms.all;
    };
  }
  ''
    mkdir -p $out/share/fonts/truetype
    for cut in Rounded Sharp; do
      python3 -I "$script" "${material-symbols}/share/fonts/truetype/MaterialSymbols$cut[FILL,GRAD,opsz,wght].ttf" \
        "$names" "Kurashi Symbols $cut" "$out/share/fonts/truetype/KurashiSymbols$cut.ttf"
    done
  ''
