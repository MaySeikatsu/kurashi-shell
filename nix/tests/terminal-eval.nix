# Evaluation tests for the terminal's Home-Manager options (W83): the host package and the mod on or off, the
# `Mod+Grave` bind (niri accepts it) and `keybind = null`, and kurashid's PATH with the host (alone and with the web
# dock's). Nothing is activated. As webdock-eval.nix:
#   timeout 3600 nix build --no-link --impure -f nix/tests/terminal-eval.nix
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
  system = pkgs.stdenv.hostPlatform.system;
  plain = builtins.unsafeDiscardStringContext;
  one = x: if lib.isList x then lib.concatStringsSep " " x else x;

  stub = pkgs.runCommand "kurashi-stub" { } ''
    mkdir -p $out/bin $out/share/kurashi/frontend
    touch $out/bin/kurashid $out/bin/kurashi $out/share/kurashi/frontend/shell.qml
    chmod +x $out/bin/kurashid $out/bin/kurashi
  '';
  termStub = pkgs.runCommand "kurashi-terminal-stub" { } ''
    mkdir -p $out/bin
    touch $out/bin/qs-terminal
    chmod +x $out/bin/qs-terminal
  '';
  webdockStub = pkgs.runCommand "kurashi-webdock-stub" { } ''
    mkdir -p $out/bin
    touch $out/bin/qs-webengine
    chmod +x $out/bin/qs-webengine
  '';
  self.packages.${system} = {
    kurashi = stub;
    kurashi-webdock = webdockStub;
    quickshell-terminal = termStub;
  };

  evalHm =
    kurashi:
    import "${hmSrc}/modules" {
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
          programs.kurashi = kurashi;
        };
    };

  on = evalHm {
    enable = true;
    niri.binds.enable = true;
    terminal.enable = true;
  };
  off = evalHm {
    enable = true;
    niri.binds.enable = true;
  };
  noBind = evalHm {
    enable = true;
    niri.binds.enable = true;
    terminal = {
      enable = true;
      keybind = null;
    };
  };
  both = evalHm {
    enable = true;
    terminal.enable = true;
    webdock.enable = true;
  };
  noKurashi = evalHm { terminal.enable = true; };

  refused = c: !(builtins.tryEval (builtins.seq c.config.home.packages true)).success;
  niriText = c: plain c.config.xdg.configFile."niri/kurashi-binds.kdl".text;
  kurashiBin = plain "${stub}/bin/kurashi";
  moduleBind = "    Mod+Grave repeat=false { spawn \"${kurashiBin}\" \"act\" \"terminal.toggle\"; }";
  packagePaths = c: map (p: p.outPath) c.config.home.packages;
  daemonExec = c: one c.config.systemd.user.services.kurashid.Service.ExecStart;

  checks = [
    [ "terminal on: its host package is installed" (lib.elem termStub.outPath (packagePaths on)) ]
    [ "terminal off: no host package" (!(lib.elem termStub.outPath (packagePaths off))) ]
    [ "terminal on: Mod+Grave runs terminal.toggle" (lib.hasInfix moduleBind (niriText on)) ]
    [ "terminal off: no Mod+Grave bind" (!(lib.hasInfix "Mod+Grave" (niriText off))) ]
    [ "keybind = null: no bind, the package still there" (!(lib.hasInfix "Mod+Grave" (niriText noBind)) && lib.elem termStub.outPath (packagePaths noBind)) ]
    [ "terminal on: kurashid starts through the hosts' PATH wrapper" (daemonExec on != "${stub}/bin/kurashid") ]
    [ "terminal off: kurashid runs the package directly" (daemonExec off == "${stub}/bin/kurashid") ]
    [ "the terminal needs programs.kurashi.enable" (refused noKurashi) ]
    [ "the valid configurations are accepted" (!(refused on) && !(refused off) && !(refused noBind) && !(refused both)) ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);

  niriValidate = pkgs.runCommand "kurashi-terminal-niri-validate" { nativeBuildInputs = [ pkgs.niri ]; } ''
    set -e
    export HOME=$TMPDIR
    mkdir check
    cp ${on.config.xdg.configFile."niri/kurashi-binds.kdl".source} check/kurashi-binds.kdl
    printf '%s\n' 'binds {' '    Mod+Q { close-window; }' '}' 'include "kurashi-binds.kdl"' > check/config.kdl
    niri validate -c check/config.kdl
    touch $out
  '';
in
assert lib.assertMsg (failed == [ ]) "terminal-eval failed: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-terminal-eval"
  {
    managedOn = on.config.xdg.configFile."kurashi/managed.toml".source;
    niriValidated = niriValidate;
    kurashidOn = daemonExec on;
    kurashidBoth = daemonExec both;
  }
  ''
    grep -q 'loaded = .*"terminal"' $managedOn
    grep -q 'enabled = .*"terminal"' $managedOn
    grep -q '${termStub}/bin' $kurashidOn
    grep -q '${stub}/bin/kurashid' $kurashidOn
    # With the web dock too, one wrapper carries both hosts.
    grep -q '${termStub}/bin' $kurashidBoth
    grep -q '${webdockStub}/bin' $kurashidBoth
    touch $out
  ''
