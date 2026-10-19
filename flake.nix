{
  description = "Kurashi-shell (暮らし) — a quiet, honest, moddable Wayland shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: rec {
        kurashi = pkgs.callPackage ./nix/package.nix { };
        # The web dock's host process (K38, K39); not part of the base closure.
        quickshell-webengine = pkgs.callPackage ./nix/quickshell-webengine.nix { };
        default = kurashi;
      });

      # `nix run .#<app>`: default (live session), settings, mock, sandbox. See nix/apps.nix.
      apps = nixpkgs.lib.genAttrs systems (
        system:
        (import ./nix/apps.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          kurashi = self.packages.${system}.kurashi;
        }).apps
      );

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          name = "kurashi";
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi ];
          packages = with pkgs; [
            # Rust
            cargo rustc clippy rustfmt rust-analyzer cargo-nextest
            # Workflow
            just jq python3 git
            # Frontend default (K3 candidate 1) + headless test compositor
            quickshell sway grim wayland-utils
            # Web dock host (K39) + typing into it in sandbox tests
            self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-webengine wtype
            # Bench harness
            strace (pkgs.perf or linuxPackages.perf) procps dbus hyperfine
          ];
          RUST_BACKTRACE = "1";
          shellHook = ''
            echo "kurashi dev shell — 'just' lists tasks"
          '';
        };
      });

      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/hm-module.nix self;

      checks = forAll (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      });

      formatter = forAll (pkgs: pkgs.nixfmt-rfc-style);
    };
}
