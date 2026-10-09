self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kurashi;
  toml = pkgs.formats.toml { };
  envList = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.extraEnvironment;

  # Defaults of niri.binds.keys (niri key name -> kurashi action id, see docs/niri-binds.kdl).
  niriDefaultKeys = {
    "Mod+Space" = "launcher.toggle";
    "Mod+N" = "notifications.center";
    "Mod+Shift+E" = "session.menu";
    "Super+Alt+L" = "session.lock";
    "XF86AudioRaiseVolume" = "audio.volume.up";
    "XF86AudioLowerVolume" = "audio.volume.down";
    "XF86AudioMute" = "audio.mute.toggle";
    "XF86MonBrightnessUp" = "brightness.up";
    "XF86MonBrightnessDown" = "brightness.down";
  };
  # The only binds that repeat while held. Niri repeats by default, so every other bind gets
  # repeat=false: a toggle or a menu would otherwise flip on each repeat.
  niriRepeating = [ "audio.volume.up" "audio.volume.down" "brightness.up" "brightness.down" ];
  niriBindProps =
    action:
    # Session menu and lock stay reachable while a VM or remote desktop inhibits shortcuts.
    lib.optional (lib.hasPrefix "session." action) "allow-inhibiting=false"
    # Media keys work while locked, as niri's own volume keys do.
    ++ lib.optional (lib.hasPrefix "audio." action || lib.hasPrefix "brightness." action) "allow-when-locked=true"
    ++ lib.optional (!(lib.elem action niriRepeating)) "repeat=false";
  niriBindLine =
    key: action:
    let
      lhs = lib.concatStringsSep " " ([ key ] ++ niriBindProps action);
    in
    "    ${lhs} { spawn \"${cfg.package}/bin/kurashi\" \"act\" \"${action}\"; }";
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

    niri.binds = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Write {file}`~/.config/niri/kurashi-binds.kdl`, a `binds` block for the keys of
          {option}`programs.kurashi.niri.binds.keys`. niri reads it once its config includes it
          (`include "kurashi-binds.kdl"`, niri 25.11 or later). Put the include after your own
          `binds {}` block: later binds override earlier ones. On older niri, paste the `binds`
          block into your config instead. Nothing is written while this is off.
        '';
      };

      keys = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr (lib.types.strMatching "[a-z0-9._-]+"));
        default = { };
        example = lib.literalExpression ''{ "Mod+L" = "session.lock"; XF86AudioMute = null; }'';
        description = ''
          niri key name to kurashi action id (the argument of `kurashi act`). Entries add to the
          defaults and override them for the same key; `null` removes a default. The defaults:
          `Mod+Space` launcher.toggle, `Mod+N` notifications.center, `Mod+Shift+E` session.menu,
          `Super+Alt+L` session.lock, `XF86AudioRaiseVolume` and `XF86AudioLowerVolume`
          audio.volume.up and audio.volume.down, `XF86AudioMute` audio.mute.toggle,
          `XF86MonBrightnessUp` and `XF86MonBrightnessDown` brightness.up and brightness.down.
          The niri defaults for the same keys are replaced (see docs/niri-binds.kdl).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Defaults as entries with mkDefault: a user entry for the same key wins, the others merge in.
    programs.kurashi.niri.binds.keys = lib.mapAttrs (_: lib.mkDefault) niriDefaultKeys;

    assertions = [
      {
        assertion = lib.all (key: builtins.match "[A-Za-z0-9_+-]+" key != null) (lib.attrNames cfg.niri.binds.keys);
        message = "programs.kurashi.niri.binds.keys: niri key names may use letters, digits, _, + and - only.";
      }
    ];

    # `settings` may be empty while `enforce` is set; the file is still written then so the
    # flag is never silently dropped.
    xdg.configFile."kurashi/managed.toml" = lib.mkIf (cfg.settings != { } || cfg.enforce) {
      source = toml.generate "kurashi-managed.toml" (cfg.settings // { _managed.enforce = cfg.enforce; });
    };

    # niri reads this only when its config includes it (see programs.kurashi.niri.binds.enable).
    xdg.configFile."niri/kurashi-binds.kdl" = lib.mkIf cfg.niri.binds.enable {
      text = ''
        // Generated by Home-Manager from programs.kurashi.niri.binds: change the options, not this file.
        // Include it after your own binds {} block in ~/.config/niri/config.kdl (niri 25.11 or later).
        binds {
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList niriBindLine (lib.filterAttrs (_: action: action != null) cfg.niri.binds.keys)
        )}
        }
      '';
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
        # launch.sh pins the EGL vendor of the GPU the session renders on (K16, K-hybrid-egl). It asks
        # wayland-info for the compositor's main device, which the service gets by store path like qs.
        ExecStart = "${cfg.package}/share/kurashi/frontend/launch.sh";
        Restart = "on-failure";
        RestartSec = 1;
        RestartSteps = 5;
        RestartMaxDelaySec = 30;
        Environment = envList ++ [
          "KURASHI_QS=${lib.getExe' cfg.frontend.package "qs"}"
          "KURASHI_WAYLAND_INFO=${lib.getExe' pkgs.wayland-utils "wayland-info"}"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
