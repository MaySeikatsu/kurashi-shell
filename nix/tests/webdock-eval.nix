# Evaluation tests for the web dock's options (K38, K40; card W20-webdock-nix). Home-Manager: the package and the mod on
# or off, the pins and settings in the Nix layer, the `Mod+B` bind and `keybind = null`, the merge with the user's own
# mod lists, the refusals, and the PATH kurashid gets for the host. NixOS: the package. Nothing is activated.
# Run it wrapped in a timeout, as hm-eval.nix (it needs --impure for builtins.currentSystem):
#   timeout 3600 nix build --no-link --impure -f nix/tests/webdock-eval.nix
# nixpkgs comes from the repo's flake.lock; home-manager is pinned here, as in hm-eval.nix.
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

  # Stand-ins for the two packages: the same layout, nothing compiled.
  stub = pkgs.runCommand "kurashi-stub" { } ''
    mkdir -p $out/bin $out/share/kurashi/frontend
    touch $out/bin/kurashid $out/bin/kurashi $out/share/kurashi/frontend/shell.qml
    chmod +x $out/bin/kurashid $out/bin/kurashi
  '';
  webdockStub = pkgs.runCommand "kurashi-webdock-stub" { } ''
    mkdir -p $out/bin
    touch $out/bin/qs-webengine $out/bin/xdg-open
    chmod +x $out/bin/qs-webengine $out/bin/xdg-open
  '';
  self.packages.${system} = {
    kurashi = stub;
    kurashi-webdock = webdockStub;
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

  pins = [
    {
      id = "news";
      title = "News";
      target = "https://example.org/news";
      view = "mobile";
    }
    {
      id = "sysmon";
      title = "System";
      target = "mod:sysmon:panel";
      profile = "work";
      icon = "chart";
    }
  ];

  # Dock on with pins and settings; the bind at its default; the niri file written.
  on = evalHm {
    enable = true;
    niri.binds.enable = true;
    webdock = {
      enable = true;
      inherit pins;
      edge = "left";
      reopen_last = false;
    };
  };
  # Dock off (the default): no package, no mod, no bind.
  off = evalHm {
    enable = true;
    niri.binds.enable = true;
  };
  # `keybind = null`: dock on, no bind.
  noBind = evalHm {
    enable = true;
    niri.binds.enable = true;
    webdock = {
      enable = true;
      keybind = null;
    };
  };
  # The user's own mod list merges with the dock's.
  merged = evalHm {
    enable = true;
    settings.mods.enabled = [ "sysmon" ];
    webdock.enable = true;
  };
  # The bind is on, niri binds are off: nothing is written, and a warning says so.
  noNiri = evalHm {
    enable = true;
    webdock.enable = true;
  };
  # Refused: two pins with one id.
  dupPins = evalHm {
    enable = true;
    webdock = {
      enable = true;
      pins = [
        {
          id = "a";
          title = "A";
          target = "https://a.example";
        }
        {
          id = "a";
          title = "B";
          target = "https://b.example";
        }
      ];
    };
  };
  # Refused: the dock without kurashi.
  noKurashi = evalHm { webdock.enable = true; };

  # Home-Manager throws when an assertion fails (modules/default.nix), so a refused configuration is one whose
  # evaluation throws.
  refused = c: !(builtins.tryEval (builtins.seq c.config.home.packages true)).success;
  niriText = c: plain c.config.xdg.configFile."niri/kurashi-binds.kdl".text;
  kurashiBin = plain "${stub}/bin/kurashi";
  moduleBind = "    Mod+B repeat=false { spawn \"${kurashiBin}\" \"act\" \"webdock.toggle\"; }";
  packagePaths = c: map (p: p.outPath) c.config.home.packages;
  daemonExec = c: one c.config.systemd.user.services.kurashid.Service.ExecStart;

  # NixOS: the package only (the settings are Home-Manager's).
  nixosEval =
    webdockEnable:
    (import "${nixpkgsSrc}/nixos/lib/eval-config.nix") {
      inherit system;
      modules = [
        (import ../nixos-module.nix self)
        { programs.kurashi.enable = true; programs.kurashi.webdock.enable = webdockEnable; }
      ];
    };
  nixosPaths = c: map (p: p.outPath) c.config.environment.systemPackages;

  checks = [
    [ "dock on: its package is in home.packages" (lib.elem webdockStub.outPath (packagePaths on)) ]
    [ "dock off: no web dock package" (!(lib.elem webdockStub.outPath (packagePaths off))) ]
    [ "dock off: no managed.toml (no mod on, no settings)" (!(off.config.xdg.configFile ? "kurashi/managed.toml")) ]
    [ "dock on: kurashid starts through the dock's PATH wrapper" (daemonExec on != "${stub}/bin/kurashid") ]
    [ "dock off: kurashid runs the package directly" (daemonExec off == "${stub}/bin/kurashid") ]
    [ "dock on: Mod+B runs webdock.toggle through the package CLI" (lib.hasInfix moduleBind (niriText on)) ]
    [ "dock on: the other binds are still there" (lib.hasInfix "    Mod+Space repeat=false" (niriText on)) ]
    [ "dock off: no Mod+B bind" (!(lib.hasInfix "Mod+B" (niriText off))) ]
    [ "keybind = null: no Mod+B bind" (!(lib.hasInfix "Mod+B" (niriText noBind))) ]
    [ "keybind = null: the dock's package is still installed" (lib.elem webdockStub.outPath (packagePaths noBind)) ]
    [ "bind without niri binds: no file, a warning" (!(noNiri.config.xdg.configFile ? "niri/kurashi-binds.kdl") && noNiri.config.warnings != [ ]) ]
    [ "duplicate pin ids are refused" (refused dupPins) ]
    [ "the dock needs programs.kurashi.enable" (refused noKurashi) ]
    [ "the valid configurations are accepted" (!(refused on) && !(refused off) && !(refused noBind) && !(refused merged) && !(refused noNiri)) ]
    [ "NixOS: the dock's package is installed with the dock on" (lib.elem webdockStub.outPath (nixosPaths (nixosEval true))) ]
    [ "NixOS: no dock package with the dock off" (!(lib.elem webdockStub.outPath (nixosPaths (nixosEval false)))) ]
    [ "NixOS: kurashi is installed either way" (lib.elem stub.outPath (nixosPaths (nixosEval false))) ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);

  # niri from the same nixpkgs accepts the generated file with the dock's bind. `niri validate` only parses it.
  niriValidate = pkgs.runCommand "kurashi-webdock-niri-validate" { nativeBuildInputs = [ pkgs.niri ]; } ''
    set -e
    export HOME=$TMPDIR
    mkdir check
    cp ${on.config.xdg.configFile."niri/kurashi-binds.kdl".source} check/kurashi-binds.kdl
    printf '%s\n' 'binds {' '    Mod+Q { close-window; }' '}' 'include "kurashi-binds.kdl"' > check/config.kdl
    niri validate -c check/config.kdl
    touch $out
  '';
in
assert lib.assertMsg (failed == [ ]) "webdock-eval failed: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-webdock-eval"
  {
    managedOn = on.config.xdg.configFile."kurashi/managed.toml".source;
    managedMerged = merged.config.xdg.configFile."kurashi/managed.toml".source;
    niriValidated = niriValidate;
    kurashidOn = daemonExec on;
  }
  ''
    # The dock's settings and pins, in the nix layer (managed.toml).
    grep -q 'edge = "left"' $managedOn
    grep -q 'reopen_last = false' $managedOn
    grep -q 'id = "news"' $managedOn
    grep -q 'target = "mod:sysmon:panel"' $managedOn
    grep -q 'profile = "work"' $managedOn
    grep -q 'icon = "chart"' $managedOn
    # One view is set (the news pin); the sysmon pin takes the mod's default.
    test "$(grep -c 'view = ' $managedOn)" = 1
    grep -q 'loaded = .*"webdock"' $managedOn
    grep -q 'enabled = .*"webdock"' $managedOn
    # The user's own mod list survives next to the dock.
    grep -q 'enabled = .*"sysmon"' $managedMerged
    grep -q 'enabled = .*"webdock"' $managedMerged
    # The wrapper prefixes the dock's commands onto kurashid's PATH and still runs the daemon.
    grep -q '${webdockStub}/bin' $kurashidOn
    grep -q '${stub}/bin/kurashid' $kurashidOn
    # The docs snippet carries the bind the module writes.
    grep -qxF '    Mod+B repeat=false { spawn "kurashi" "act" "webdock.toggle"; }' ${../../docs/niri-binds.kdl}
    touch $out
  ''
