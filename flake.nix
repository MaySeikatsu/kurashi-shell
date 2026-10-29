{
  description = "Kurashi-shell (暮らし) — a quiet, honest, moddable Wayland shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Rust builds with a cached dependency derivation (I292).
  inputs.crane.url = "github:ipetkov/crane";

  outputs = { self, nixpkgs, crane }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: rec {
        kurashi = pkgs.callPackage ./nix/package.nix { craneLib = crane.mkLib pkgs; };
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
          # The package is a join (nix/package.nix); its Rust build inputs come from passthru.
          packages = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi.rustNativeBuildInputs
            ++ self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi.rustBuildInputs
            ++ (with pkgs; [
            # Rust
            cargo rustc clippy rustfmt rust-analyzer cargo-nextest
            # Workflow
            # python3 with fontTools: tools/check-icon-names.sh (W41, row 446) regenerates nix/icon-names.txt from the font
            just jq (python3.withPackages (ps: [ ps.fonttools ])) git
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
          ]);
          RUST_BACKTRACE = "1";
          # The fonts the shell draws with (HM `programs.kurashi.fonts`), visible to fontconfig through its
          # xdg data dirs, so sandbox screenshots show icons and every decor look without a system install.
          # The icon subset first (W41, row 445): the theme prefers it, and Material Symbols is the fallback.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.lib.concatMapStringsSep ":" (f: "${f}/share") (with pkgs; [ (callPackage ./nix/icon-font.nix { }) material-symbols nunito inter jetbrains-mono noto-fonts noto-fonts-cjk-serif (google-fonts.override { fonts = [ "Kalam" "KleeOne" ]; }) ])}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
            echo "kurashi dev shell — 'just' lists tasks"
          '';
        };
      });

      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/hm-module.nix self;

      checks = forAll (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
        # The workspace's `cargo test` (I293): out of the package build, reusing its dependency artifacts.
        tests = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi.cargoTests;
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
