self:
{ config, lib, pkgs, ... }:

# System-level bits only. The shell itself (kurashid + frontend user services, settings) is run by
# the Home-Manager module; nothing here starts a user unit (K11).
let
  cfg = config.programs.kurashi;
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell system prerequisites (package, PAM, power/battery service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Battery/power state comes from UPower over D-Bus; mkDefault so hosts can opt out.
    services.upower.enable = lib.mkDefault true;

    # PAM entry for the lockscreen (M5).
    security.pam.services.kurashi = { };

    # Brightness needs no extra rule: logind's SetBrightness D-Bus call is permitted for the
    # active local session, which is what kurashid uses (no udev/video-group hacks).
  };
}
