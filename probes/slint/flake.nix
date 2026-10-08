{
  description = "Kurashi bake-off probe: Slint (software renderer + own layer-shell glue)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      libs = with pkgs; [ wayland libxkbcommon fontconfig freetype ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ cargo rustc pkg-config clang gcc ] ++ libs;
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
      };
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "kurashi-probe-slint";
        version = "0.0.1";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
        buildInputs = libs;
        postFixup = ''
          wrapProgram $out/bin/kurashi-probe-slint --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath libs}
        '';
        doCheck = false;
      };
    };
}
