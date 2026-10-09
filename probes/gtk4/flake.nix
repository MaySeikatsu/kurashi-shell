{
  description = "Kurashi bake-off probe: gtk4-rs + gtk4-layer-shell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      libs = with pkgs; [ gtk4 gtk4-layer-shell wayland libxkbcommon libepoxy glib pango cairo gdk-pixbuf graphene harfbuzz fontconfig vulkan-loader libGL ];
    in
    {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "probe-gtk4";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = with pkgs; [ pkg-config wrapGAppsHook4 ];
        buildInputs = libs;
      };
      apps.${system}.default = { type = "app"; program = "${self.packages.${system}.default}/bin/probe-gtk4"; };

      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [ pkg-config cargo rustc clippy rustfmt ];
        buildInputs = libs;
        packages = with pkgs; [ sway grim wayland-utils python3 strace jq ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
      };
    };
}
