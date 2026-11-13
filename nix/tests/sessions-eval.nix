# Evaluation tests for the sessions' Home-Manager options (W86, docs/ux/sessions.md): off ships nothing (no noren, no
# zellij, the daemon unwrapped, the mod not turned on); on ships noren with zellij, zoxide, fzf, git and eza in
# home.packages and on kurashid's PATH and turns the mod on; `sessions.package` overrides noren. Nothing is activated.
# As terminal-eval.nix:
#   timeout 3600 nix build --no-link --impure -f nix/tests/sessions-eval.nix
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
  one = x: if lib.isList x then lib.concatStringsSep " " x else x;

  binStub = name: bin: pkgs.runCommand name { } ''
    mkdir -p $out/bin
    touch $out/bin/${bin}
    chmod +x $out/bin/${bin}
  '';
  stub = pkgs.runCommand "kurashi-stub" { } ''
    mkdir -p $out/bin $out/share/kurashi/frontend
    touch $out/bin/kurashid $out/bin/kurashi $out/share/kurashi/frontend/shell.qml
    chmod +x $out/bin/kurashid $out/bin/kurashi
  '';
  norenStub = binStub "noren-stub" "noren";
  otherNoren = binStub "noren-other" "noren";
  self.packages.${system} = {
    kurashi = stub;
    kurashi-webdock = binStub "kurashi-webdock-stub" "qs-webengine";
    quickshell-terminal = binStub "kurashi-terminal-stub" "qs-terminal";
    noren = norenStub;
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
    sessions.enable = true;
  };
  off = evalHm { enable = true; };
  other = evalHm {
    enable = true;
    sessions = {
      enable = true;
      package = otherNoren;
    };
  };
  withTerminal = evalHm {
    enable = true;
    sessions.enable = true;
    terminal.enable = true;
  };
  noKurashi = evalHm { sessions.enable = true; };

  refused = c: !(builtins.tryEval (builtins.seq c.config.home.packages true)).success;
  packagePaths = c: map (p: p.outPath) c.config.home.packages;
  has = c: p: lib.elem p.outPath (packagePaths c);
  daemonExec = c: one c.config.systemd.user.services.kurashid.Service.ExecStart;
  tools = with pkgs; [ zellij zoxide fzf git eza ];

  checks = [
    [ "off: no noren" (!(has off norenStub)) ]
    [ "off: none of noren's tools" (lib.all (t: !(has off t)) tools) ]
    [ "off: kurashid runs the package directly" (daemonExec off == "${stub}/bin/kurashid") ]
    [ "on: noren is installed" (has on norenStub) ]
    [ "on: zellij, zoxide, fzf, git and eza are installed" (lib.all (has on) tools) ]
    [ "on: kurashid starts through the PATH wrapper" (daemonExec on != "${stub}/bin/kurashid") ]
    [ "package overrides noren" (has other otherNoren && !(has other norenStub)) ]
    [ "sessions needs programs.kurashi.enable" (refused noKurashi) ]
    [ "the valid configurations are accepted" (!(refused on) && !(refused off) && !(refused other) && !(refused withTerminal)) ]
  ];
  failed = map (c: lib.head c) (lib.filter (c: !(lib.elemAt c 1)) checks);
in
assert lib.assertMsg (failed == [ ]) "sessions-eval failed: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "kurashi-sessions-eval"
  {
    managedOn = on.config.xdg.configFile."kurashi/managed.toml".source;
    managedOff = off.config.xdg.configFile."kurashi/managed.toml".source or "/dev/null";
    kurashidOn = daemonExec on;
    kurashidOther = daemonExec other;
    kurashidBoth = daemonExec withTerminal;
  }
  ''
    grep -q 'loaded = .*"sessions"' $managedOn
    grep -q 'enabled = .*"sessions"' $managedOn
    ! grep -q '"sessions"' $managedOff
    # noren and its tools on the daemon's PATH, by store path.
    grep -q '${norenStub}/bin' $kurashidOn
    grep -q '${pkgs.zellij}/bin' $kurashidOn
    grep -q '${pkgs.zoxide}/bin' $kurashidOn
    grep -q '${pkgs.fzf}/bin' $kurashidOn
    grep -q '${stub}/bin/kurashid' $kurashidOn
    grep -q '${otherNoren}/bin' $kurashidOther
    # With the terminal too, one wrapper carries both.
    grep -q '${norenStub}/bin' $kurashidBoth
    grep -q 'qs-terminal\|kurashi-terminal-stub' $kurashidBoth
    touch $out
  ''
