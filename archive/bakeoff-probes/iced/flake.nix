{
  description = "kurashi bake-off probe: iced + iced_layershell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      libs = with pkgs; [ wayland libxkbcommon vulkan-loader libGL fontconfig freetype ];
    in
    {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "kurashi-probe-iced";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = [ pkgs.pkg-config pkgs.makeWrapper ];
        buildInputs = libs;
        postFixup = ''
          wrapProgram $out/bin/kurashi-probe-iced \
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath libs}
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          cargo rustc pkg-config
          # bench / sandbox tooling (same as root shell)
          python3 jq git sway grim strace procps dbus wayland-utils
        ] ++ libs;
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
      };
    };
}
