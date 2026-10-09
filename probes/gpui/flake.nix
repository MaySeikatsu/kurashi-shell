{
  description = "kurashi bake-off probe: gpui";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      libs = with pkgs; [
        wayland libxkbcommon vulkan-loader libGL fontconfig freetype
        xorg.libxcb xorg.libX11 openssl alsa-lib zlib
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          cargo rustc pkg-config cmake clang mold
          sway grim wayland-utils python3 strace procps dbus jq
        ];
        buildInputs = libs;
        CARGO_BUILD_JOBS = "3";
        RUSTFLAGS = "-C link-arg=-Wl,-rpath,${pkgs.lib.makeLibraryPath libs}";
        FONTCONFIG_FILE = pkgs.makeFontsConf {
          fontDirectories = [ pkgs.inter pkgs.noto-fonts-cjk-sans pkgs.dejavu_fonts ];
        };
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
        shellHook = ''
          export CARGO_BUILD_JOBS=3
        '';
      };
    };
}
