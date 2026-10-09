{
  description = "kurashi bake-off probe: quickshell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      run = pkgs.writeShellScriptBin "kurashi-probe-quickshell" ''
        exec ${pkgs.quickshell}/bin/qs -p ${./.} "$@"
      '';
    in {
      packages.x86_64-linux.default = run;
      apps.x86_64-linux.default = { type = "app"; program = "${run}/bin/kurashi-probe-quickshell"; };
      devShells.x86_64-linux.default = pkgs.mkShell {
        # qtshadertools provides `qsb` to rebuild shader.frag.qsb
        packages = [ pkgs.quickshell pkgs.qt6.qtshadertools pkgs.sway pkgs.grim ];
      };
    };
}
