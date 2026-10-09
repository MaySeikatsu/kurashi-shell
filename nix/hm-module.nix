self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kurashi;
  toml = pkgs.formats.toml { };
  envList = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.extraEnvironment;
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package (daemon + CLI + frontend data).";
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      example = lib.literalExpression ''{ theme.palette = "wa-iro"; bar.main.edge = "top"; }'';
      description = ''
        Declarative settings, written to {file}`~/.config/kurashi/managed.toml`.
        They form the `nix` provenance layer (K15): above schema defaults, below theme
        recipes, profiles and live user changes — Settings shows "set by Home-Manager".
        The live user file {file}`config.toml` stays writable by the daemon.
      '';
    };

    enforce = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Treat {option}`settings` as forced values (`forced:nix`): they win over profiles and
        user changes, and Settings shows those controls as locked with the reason.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { RUST_LOG = "kurashid=debug"; };
      description = ''
        Extra environment variables for both services. `KURASHI_DATA_DIR` is deliberately not
        set: the binary knows its own prefix (package.nix bakes it in).
      '';
    };

    frontend = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the Quickshell frontend as a systemd user service next to kurashid.";
      };
      package = lib.mkPackageOption pkgs "quickshell" { };
    };

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run kurashid (and the frontend) as systemd user services bound to the graphical session.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # `settings` may be empty while `enforce` is set; the file is still written then so the
    # flag is never silently dropped.
    xdg.configFile."kurashi/managed.toml" = lib.mkIf (cfg.settings != { } || cfg.enforce) {
      source = toml.generate "kurashi-managed.toml" (cfg.settings // { _managed.enforce = cfg.enforce; });
    };

    systemd.user.services.kurashid = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Kurashi shell daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/kurashid";
        Restart = "on-failure";
        # Backoff 1 s -> 30 s so a crash loop does not spin (Ma).
        RestartSec = 1;
        RestartSteps = 5;
        RestartMaxDelaySec = 30;
        Environment = envList;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Requires (not BindsTo): a daemon restart must not kill the frontend; it reconnects itself.
    systemd.user.services.kurashi-frontend = lib.mkIf (cfg.systemd.enable && cfg.frontend.enable) {
      Unit = {
        Description = "Kurashi shell frontend (Quickshell)";
        PartOf = [ "graphical-session.target" ];
        Requires = [ "kurashid.service" ];
        After = [ "graphical-session.target" "kurashid.service" ];
      };
      Service = {
        Type = "simple";
        # launch.sh pins the EGL vendor on single-GPU NVIDIA machines (-13 MiB, K16).
        ExecStart = "${cfg.package}/share/kurashi/frontend/launch.sh";
        Restart = "on-failure";
        RestartSec = 1;
        RestartSteps = 5;
        RestartMaxDelaySec = 30;
        Environment = envList ++ [ "KURASHI_QS=${lib.getExe' cfg.frontend.package "qs"}" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
