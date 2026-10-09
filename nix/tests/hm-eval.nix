# Evaluation test for the Home-Manager module: `nix build --no-link -f nix/tests/hm-eval.nix`.
# Builds the activation package for a test user with the module enabled and asserts the unit
# files. Nothing is activated. nixpkgs comes from the repo's flake.lock; home-manager is pinned
# here (it is not a flake input; flake.nix is outside this test's ownership).
let
  lock = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.nixpkgs.locked;
  nixpkgsSrc = builtins.fetchTree {
    type = "github";
    inherit (lock) owner repo rev narHash;
  };
  hmSrc = builtins.fetchTree {
    type = "github";
    owner = "nix-community";
    repo = "home-manager";
    rev = "aa23f720d022187228bc264f759aef6b80233bcf";
    narHash = "sha256-+lrD+sxc2RKUWXRBAcggn7uBCFeJgnV75jD/cz7gJRA=";
  };
  pkgs = import nixpkgsSrc { system = builtins.currentSystem; };
  inherit (pkgs) lib;

  # Stand-in for the Rust build: same layout, no compile.
  stub = pkgs.runCommand "kurashi-stub" { } ''
    mkdir -p $out/bin $out/share/kurashi/frontend
    touch $out/bin/kurashid $out/share/kurashi/frontend/shell.qml
  '';
  self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi = stub;

  hm = import "${hmSrc}/modules" {
    inherit pkgs;
    check = false;
    configuration =
      { ... }:
      {
        imports = [ (import ../hm-module.nix self) ];
        home = {
          username = "tester";
          homeDirectory = "/home/tester";
          stateVersion = "24.11";
        };
        programs.kurashi = {
          enable = true;
          settings.theme.palette = "wa-iro";
          enforce = true;
          extraEnvironment.RUST_LOG = "kurashid=debug";
        };
      };
  };

  cfg = hm.config;
  daemon = cfg.systemd.user.services.kurashid;
  front = cfg.systemd.user.services.kurashi-frontend;
  # HM normalises scalar unit keys to lists.
  one = x: if lib.isList x then lib.concatStringsSep " " x else x;
  qs = lib.getExe' pkgs.quickshell "qs";

  checks = [
    [ "kurashid ExecStart" (one daemon.Service.ExecStart == "${stub}/bin/kurashid") ]
    [ "kurashid bound to graphical session" (daemon.Install.WantedBy == [ "graphical-session.target" ] && daemon.Unit.PartOf == [ "graphical-session.target" ]) ]
    [ "kurashid does not set KURASHI_DATA_DIR" (!(lib.any (lib.hasPrefix "KURASHI_DATA_DIR") daemon.Service.Environment)) ]
    [ "kurashid restarts on failure" (one daemon.Service.Restart == "on-failure") ]
    [ "frontend ExecStart" (one front.Service.ExecStart == "${stub}/share/kurashi/frontend/launch.sh") ]
    [ "frontend gets quickshell via KURASHI_QS" (lib.elem "KURASHI_QS=${qs}" front.Service.Environment) ]
    [ "frontend Requires (not BindsTo) kurashid" (front.Unit.Requires == [ "kurashid.service" ] && !(front.Unit ? BindsTo)) ]
    [ "frontend ordered after kurashid" (lib.elem "kurashid.service" front.Unit.After) ]
    [ "extraEnvironment reaches both" (daemon.Service.Environment == [ "RUST_LOG=kurashid=debug" ] && lib.elem "RUST_LOG=kurashid=debug" front.Service.Environment) ]
    [ "managed.toml generated" (cfg.xdg.configFile ? "kurashi/managed.toml") ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);
in
assert lib.assertMsg (failed == [ ]) "hm-eval failed: ${builtins.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-hm-eval"
  {
    activation = cfg.home.activationPackage;
    managed = cfg.xdg.configFile."kurashi/managed.toml".source;
  }
  ''
    unit=$activation/home-files/.config/systemd/user
    grep -q "ExecStart=${stub}/bin/kurashid" $unit/kurashid.service
    grep -q "WantedBy=graphical-session.target" $unit/kurashid.service
    grep -q "Requires=kurashid.service" $unit/kurashi-frontend.service
    grep -q "ExecStart=${stub}/share/kurashi/frontend/launch.sh" $unit/kurashi-frontend.service
    grep -q "KURASHI_QS=${qs}" $unit/kurashi-frontend.service
    ! grep -q BindsTo $unit/kurashi-frontend.service
    grep -q 'palette = "wa-iro"' $managed
    grep -q 'enforce = true' $managed
    touch $out
  ''
