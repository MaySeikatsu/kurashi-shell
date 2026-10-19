let
  flake = builtins.getFlake "git+file:///home/maike/Projects/kurashi-shell";
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
in pkgs.mkShell {
  packages = [ (pkgs.python3.withPackages (p: [ p.pygobject3 ])) pkgs.gtk4 pkgs.webkitgtk_6_0 pkgs.gtk4-layer-shell pkgs.gobject-introspection pkgs.sway pkgs.grim pkgs.quickshell ];
  GTK4_LAYER_SHELL_LIB = "${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so";
}
