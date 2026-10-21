# Evaluation check of `services.kurashi.greeter` (W28; the shape of nix/tests/webdock-eval.nix). Nothing is activated:
# the NixOS configuration is only evaluated, the greeter's command script is built (it is a text file) and the
# compositor config it names is checked by `niri validate` from the same nixpkgs.
#   timeout 3600 nix build --no-link --impure -f greeter/nixos-eval.nix
let
  lock = (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes.nixpkgs.locked;
  nixpkgsSrc = builtins.fetchTree {
    type = "github";
    inherit (lock) owner repo rev narHash;
  };
  pkgs = import nixpkgsSrc { system = builtins.currentSystem; };
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  # A stand-in for the package: the same layout, nothing compiled.
  stub = pkgs.runCommand "kurashi-stub" { } ''
    mkdir -p $out/bin $out/share/kurashi/greeter
    touch $out/bin/kurashid $out/bin/kurashi $out/share/kurashi/greeter/shell.qml
    chmod +x $out/bin/kurashid $out/bin/kurashi
  '';
  self.packages.${system}.kurashi = stub;

  evalWith =
    greeter:
    (import "${nixpkgsSrc}/nixos/lib/eval-config.nix") {
      inherit system;
      modules = [
        (import ../nix/nixos-module.nix self)
        {
          users.users.alice.isNormalUser = true;
          users.users.svc.isSystemUser = true;
          users.users.svc.group = "svc";
          users.groups.svc = { };
          services.xserver.xkb.layout = "de";
          services.kurashi.greeter = greeter;
          # Enough of a system to evaluate.
          fileSystems."/".device = "/dev/null";
          boot.loader.grub.enable = false;
          system.stateVersion = "24.11";
        }
      ];
    };
  on = (evalWith { enable = true; }).config;
  sway = (evalWith { enable = true; compositor = "sway"; }).config;
  off = (evalWith { }).config;
  tmp = c: c.systemd.tmpfiles.settings."10-kurashi-greeter" or { };
  cmd = c: c.services.greetd.settings.default_session.command;

  checks = [
    [ "on: greetd is enabled" on.services.greetd.enable ]
    [ "on: greetd runs the greeter's command" (lib.hasInfix "kurashi-greeter" (cmd on)) ]
    [ "on: the greeter runs as the greeter user" (on.services.greetd.settings.default_session.user == "greeter") ]
    [ "on: the greeter's directory belongs to the greeter" ((tmp on)."/var/lib/kurashi-greeter".d.user == "greeter") ]
    [ "on: a normal user gets their slots" ((tmp on)."/var/lib/kurashi-greeter/alice.json".f.user == "alice") ]
    [ "on: and the picture slot" ((tmp on) ? "/var/lib/kurashi-greeter/alice.wallpaper") ]
    [ "on: a system user gets none" (!((tmp on) ? "/var/lib/kurashi-greeter/svc.json")) ]
    [ "on: the shell's fonts are installed" (lib.elem pkgs.material-symbols on.fonts.packages) ]
    [ "off: no greetd" (!off.services.greetd.enable) ]
    [ "off: no greeter directory" ((tmp off) == { }) ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);
in
assert lib.assertMsg (failed == [ ]) "greeter nixos-eval failed: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-greeter-eval"
  {
    nativeBuildInputs = [ pkgs.niri pkgs.sway ];
    niriCmd = cmd on;
    swayCmd = cmd sway;
  }
  ''
    set -e
    export HOME=$TMPDIR
    # The niri config the command runs: the keyboard layout from the system, the greeter, the quit after it.
    kdl=$(grep -o '/nix/store/[^ ]*-kurashi-greeter-niri.kdl' $niriCmd)
    grep -q 'layout "de"' $kdl
    grep -q 'share/kurashi/greeter/shell.qml; .*niri msg action quit' $kdl
    grep -q 'KURASHI_GREETER_DIR=/var/lib/kurashi-greeter' $niriCmd
    niri validate -c $kdl
    # The sway variant.
    conf=$(grep -o '/nix/store/[^ ]*-kurashi-greeter-sway.conf' $swayCmd)
    grep -q 'xkb_layout "de"' $conf
    grep -q 'swaymsg exit' $conf
    touch $out
  ''
