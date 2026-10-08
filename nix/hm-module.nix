self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kurashi;
  toml = pkgs.formats.toml { };
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package (daemon + CLI).";
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

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run kurashid as a systemd user service bound to the graphical session.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."kurashi/managed.toml" = lib.mkIf (cfg.settings != { }) {
      source = toml.generate "kurashi-managed.toml" (cfg.settings // { _managed.enforce = cfg.enforce; });
    };

    systemd.user.services.kurashid = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Kurashi shell daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/kurashid";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
