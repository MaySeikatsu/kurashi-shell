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
        # The web dock's package (K38): the host plus xdg-open. Home-Manager and NixOS install it with the dock on.
        kurashi-webdock = pkgs.callPackage ./nix/webdock.nix { inherit quickshell-webengine; };
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
            # Shader checks (the ghostty material shader, W37 row 402)
            glslang
            # Frontend default (K3 candidate 1) + headless test compositor
            quickshell sway grim wayland-utils
            # Shaders (K59): `qsb` compiles frontend/shaders/*.frag
            qt6.qtshadertools
            # Web dock host (K39) + typing into it in sandbox tests
            self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-webengine wtype
            # Bench harness
            strace (pkgs.perf or linuxPackages.perf) procps dbus hyperfine
          ];
          RUST_BACKTRACE = "1";
          # The fonts the shell draws with (HM `programs.kurashi.fonts`), visible to fontconfig through its
          # xdg data dirs, so sandbox screenshots show icons and every decor look without a system install.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.lib.concatMapStringsSep ":" (f: "${f}/share") (with pkgs; [ material-symbols nunito inter jetbrains-mono noto-fonts noto-fonts-cjk-serif (google-fonts.override { fonts = [ "Kalam" "KleeOne" ]; }) ])}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
            echo "kurashi dev shell — 'just' lists tasks"
          '';
        };
      });

      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/hm-module.nix self;

      checks = forAll (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
        # K39: the base closure has no QtWebEngine, the web dock's closure has one (nix/tests/closure.nix).
        webdock-closure = import ./nix/tests/closure.nix {
          inherit pkgs;
          base = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
          webdock = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi-webdock;
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt-rfc-style);
    };
}
