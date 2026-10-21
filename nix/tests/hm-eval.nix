# Evaluation test for the Home-Manager module: `nix build --no-link --impure -f nix/tests/hm-eval.nix`.
# Builds the activation package for a test user with the module enabled and asserts the unit
# files and the niri binds file. Nothing is activated. nixpkgs comes from the repo's flake.lock;
# home-manager is pinned here (it is not a flake input; flake.nix is outside this test's ownership).
# The niri part also runs `niri validate` (nixpkgs' niri) on the generated file and on
# docs/niri-binds.kdl, each included after a binds block as the README describes.
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
    touch $out/bin/kurashid $out/bin/kurashi $out/share/kurashi/frontend/shell.qml
  '';
  self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi = stub;

  base = {
    enable = true;
    settings.theme.palette = "wa-iro";
    enforce = true;
    extraEnvironment.RUST_LOG = "kurashid=debug";
  };

  evalHm = kurashi: evalHmWith kurashi { };
  evalHmWith =
    kurashi: extra:
    import "${hmSrc}/modules" {
      inherit pkgs;
      check = false;
      configuration =
        { ... }:
        {
          imports = [ (import ../hm-module.nix self) extra ];
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "24.11";
          };
          programs.kurashi = kurashi;
        };
    };

  # Main case: niri binds on, one key added, one default removed.
  hm = evalHm (
    base
    // {
      niri.binds = {
        enable = true;
        keys = {
          "Mod+L" = "session.lock";
          XF86AudioMute = null;
        };
      };
    }
  );
  # Defaults only: docs/niri-binds.kdl must carry every one of these bind lines.
  hmDefaults = evalHm (base // { niri.binds.enable = true; });
  # Binds off (the default): no file.
  hmOff = evalHm base;
  # K49: theme export with foot and kitty managed by Home-Manager.
  hmExport = evalHmWith (base // { themeExport.apps = [ "foot" "kitty" "niri" ]; }) {
    programs.foot.enable = true;
    programs.kitty.enable = true;
  };

  cfg = hm.config;
  daemon = cfg.systemd.user.services.kurashid;
  front = cfg.systemd.user.services.kurashi-frontend;
  # HM normalises scalar unit keys to lists.
  one = x: if lib.isList x then lib.concatStringsSep " " x else x;
  qs = lib.getExe' pkgs.quickshell "qs";

  # niri binds. The module writes the store path of the binary; the snippet says plain `kurashi`.
  # lib.hasInfix turns its argument into a regex, which may not carry store-path context.
  plain = builtins.unsafeDiscardStringContext;
  kurashiBin = plain "${stub}/bin/kurashi";
  niriFile = c: c.config.xdg.configFile."niri/kurashi-binds.kdl";
  niriText = c: plain (niriFile c).text;
  bindLines = text: lib.filter (l: lib.hasPrefix "    " l) (lib.splitString "\n" text);
  lineFor = key: lib.findFirst (l: lib.hasPrefix "    ${key} " l) "" (bindLines (niriText hm));
  snippetLine = l: lib.replaceStrings [ kurashiBin ] [ "kurashi" ] (plain l);
  docs = builtins.readFile ../../docs/niri-binds.kdl;

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
    [ "niri binds file written when enabled" (cfg.xdg.configFile ? "niri/kurashi-binds.kdl") ]
    [ "niri binds: Mod+Space runs the launcher through the package CLI" (lib.hasInfix "{ spawn \"${kurashiBin}\" \"act\" \"launcher.toggle\"; }" (lineFor "Mod+Space")) ]
    [ "niri binds: a custom key is added" (lib.hasInfix "{ spawn \"${kurashiBin}\" \"act\" \"session.lock\"; }" (lineFor "Mod+L")) ]
    [ "niri binds: null removes a default" (lineFor "XF86AudioMute" == "") ]
    [ "niri binds: the lock ignores inhibitors and does not repeat" (lib.hasInfix "allow-inhibiting=false repeat=false {" (lineFor "Super+Alt+L")) ]
    [ "niri binds: the lock is not allow-when-locked" (!(lib.hasInfix "allow-when-locked" (lineFor "Super+Alt+L"))) ]
    [ "niri binds: media keys work while locked" (lib.hasInfix "allow-when-locked=true {" (lineFor "XF86AudioRaiseVolume")) ]
    [ "niri binds: toggles do not repeat" (lib.hasInfix "Mod+Space repeat=false {" (lineFor "Mod+Space")) ]
    [ "niri binds: no file when disabled" (!(hmOff.config.xdg.configFile ? "niri/kurashi-binds.kdl")) ]
    [ "theme export: theme.export in the Nix layer" (hmExport.config.programs.kurashi.settings.theme.export == [ "foot" "kitty" "niri" ]) ]
    [ "theme export: foot includes its colour file" (lib.hasSuffix "/foot/kurashi-colors.ini" (hmExport.config.programs.foot.settings.main.include or "")) ]
    [ "theme export: kitty includes its colour file" (lib.hasInfix "include kurashi-colors.conf" hmExport.config.programs.kitty.extraConfig) ]
    [ "docs/niri-binds.kdl has every default bind line" (
      bindLines (niriText hmDefaults) != [ ]
      && lib.all (l: lib.hasInfix (snippetLine l) docs) (bindLines (niriText hmDefaults))
    ) ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);

  # niri from the same nixpkgs accepts the generated file and the snippet. `niri validate` only
  # parses the config; no compositor runs and the user's ~/.config/niri is not read.
  niriValidate = pkgs.runCommand "kurashi-niri-validate" { nativeBuildInputs = [ pkgs.niri ]; } ''
    set -e
    export HOME=$TMPDIR
    check() {
      mkdir "$1"
      cp "$2" "$1/kurashi-binds.kdl"
      printf '%s\n' 'binds {' '    Mod+Q { close-window; }' '}' 'include "kurashi-binds.kdl"' > "$1/config.kdl"
      niri validate -c "$1/config.kdl"
    }
    check generated ${(niriFile hm).source}
    check defaults ${(niriFile hmDefaults).source}
    check snippet ${../../docs/niri-binds.kdl}
    touch $out
  '';
in
assert lib.assertMsg (failed == [ ]) "hm-eval failed: ${builtins.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-hm-eval"
  {
    activation = cfg.home.activationPackage;
    managed = cfg.xdg.configFile."kurashi/managed.toml".source;
    niriValidated = niriValidate;
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
    test -f $activation/home-files/.config/niri/kurashi-binds.kdl
    touch $out
  ''
