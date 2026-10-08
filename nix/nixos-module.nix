self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kurashi;
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell (system-wide install + user service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Per-user daemon; per-user settings belong in the Home-Manager module.
    systemd.user.services.kurashid = {
      description = "Kurashi shell daemon";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/kurashid";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # PAM entry for the lockscreen (M5).
    security.pam.services.kurashi = { };
  };
}
