self:
{ config, lib, pkgs, ... }:

# System-level bits only. The shell itself (kurashid + frontend user services, settings) is run by
# the Home-Manager module; nothing here starts a user unit (K11).
let
  cfg = config.programs.kurashi;
  gcfg = config.services.kurashi.greeter;
  greeterDir = "/var/lib/kurashi-greeter";
  qml = "${cfg.package}/share/kurashi/greeter/shell.qml";
  qs = lib.getExe' gcfg.quickshellPackage "qs";
  xkb = config.services.xserver.xkb;

  # W28 (docs/ux/greeter.md; DMS's greeter does the same): greetd runs a minimal compositor whose only client is the
  # greeter, and the compositor quits when the greeter does (a session started, or it failed).
  niriConfig = pkgs.writeText "kurashi-greeter-niri.kdl" ''
    hotkey-overlay {
        skip-at-startup
    }
    input {
        keyboard {
            xkb {
                layout "${xkb.layout}"
                variant "${xkb.variant}"
                options "${xkb.options}"
            }
        }
    }
    layout {
        background-color "#000000"
    }
    spawn-at-startup "sh" "-c" "${qs} -p ${qml}; ${lib.getExe gcfg.niriPackage} msg action quit --skip-confirmation"
  '';
  swayConfig = pkgs.writeText "kurashi-greeter-sway.conf" ''
    input type:keyboard {
        xkb_layout "${xkb.layout}"
        xkb_variant "${xkb.variant}"
        xkb_options "${xkb.options}"
    }
    output * bg #000000 solid_color
    exec "${qs} -p ${qml}; ${gcfg.swayPackage}/bin/swaymsg exit"
  '';
  greeterCommand = pkgs.writeShellScript "kurashi-greeter" ''
    export XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland
    export KURASHI_GREETER_DIR=${greeterDir} KURASHI_DATA_DIR=${cfg.package}/share/kurashi
    # No kurashid exists before login; the greeter's Store never dials one.
    export KURASHI_SOCKET=/run/kurashi-greeter-has-no-daemon
    ${
      if gcfg.compositor == "niri" then
        "exec ${lib.getExe gcfg.niriPackage} -c ${niriConfig}"
      else
        "exec ${gcfg.swayPackage}/bin/sway --unsupported-gpu -c ${swayConfig}"
    }
  '';
  # One slot pair per user: theirs to write (kurashid's greeter_cache.rs), the greeter's to read.
  slots = lib.listToAttrs (
    lib.concatMap (u: [
      (lib.nameValuePair "${greeterDir}/${u}.json" { f = { user = u; mode = "0644"; }; })
      (lib.nameValuePair "${greeterDir}/${u}.wallpaper" { f = { user = u; mode = "0644"; }; })
      # I166: the texture's relief, ink and height maps (the user's cache is not readable by the greeter).
      (lib.nameValuePair "${greeterDir}/${u}.texture" { f = { user = u; mode = "0644"; }; })
      (lib.nameValuePair "${greeterDir}/${u}.texture-ink" { f = { user = u; mode = "0644"; }; })
      (lib.nameValuePair "${greeterDir}/${u}.texture-height" { f = { user = u; mode = "0644"; }; })
    ]) gcfg.users
  );
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell system prerequisites (package, PAM, power/battery service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package.";
    };

    # K47: the screen recorder prefers gpu-screen-recorder, which needs NixOS's capability wrapper (KMS capture).
    gpuScreenRecorder.enable = lib.mkEnableOption "gpu-screen-recorder for the screen recorder (K47), with its capability wrapper";

    # The web dock (K38) is set up in Home-Manager (programs.kurashi.webdock); this installs its host
    # package system-wide, as Home-Manager does for the user. The base closure never carries it.
    webdock = {
      enable = lib.mkEnableOption "the web dock's host package (qs-webengine with QtWebEngine, K38)";
      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi-webdock;
        description = "Web dock package: qs-webengine and xdg-open.";
      };
    };
  };

  # W28: the login screen in the shell's look (greetd + a Quickshell greeter in a minimal compositor).
  options.services.kurashi.greeter = {
    enable = lib.mkEnableOption "the Kurashi greeter: greetd with Kurashi's login screen (the last user's look)";
    compositor = lib.mkOption {
      type = lib.types.enum [ "niri" "sway" ];
      default = "niri";
      description = "The minimal compositor the greeter runs in (it shows only the greeter and quits with it).";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);
      defaultText = lib.literalExpression "every user with isNormalUser = true";
      description = ''
        Users whose look the greeter may show. Each gets `${greeterDir}/<user>.json` and `<user>.wallpaper`, owned by
        them, which their kurashid fills after every theme or wallpaper change; the greeter reads them, since it cannot
        read a home directory.
      '';
    };
    fonts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ material-symbols nunito inter jetbrains-mono noto-fonts noto-fonts-cjk-sans noto-fonts-cjk-serif quicksand comic-neue cinzel eb-garamond roboto (google-fonts.override { fonts = [ "Kalam" "KleeOne" ]; }) ];
      defaultText = lib.literalExpression "the Home-Manager module's `programs.kurashi.fonts`";
      description = "System fonts for the greeter (it runs as the greeter user, without the user's fonts); [ ] to manage them yourself.";
    };
    quickshellPackage = lib.mkPackageOption pkgs "quickshell" { };
    niriPackage = lib.mkPackageOption pkgs "niri" { };
    swayPackage = lib.mkPackageOption pkgs "sway" { };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];

      # Battery/power state comes from UPower over D-Bus; mkDefault so hosts can opt out.
      services.upower.enable = lib.mkDefault true;

      # PAM entry for the lockscreen (M5).
      security.pam.services.kurashi = { };

      # Brightness needs no extra rule: logind's SetBrightness D-Bus call is permitted for the
      # active local session, which is what kurashid uses (no udev/video-group hacks).
    })

    (lib.mkIf (cfg.enable && cfg.gpuScreenRecorder.enable) {
      programs.gpu-screen-recorder.enable = true;
    })

    (lib.mkIf gcfg.enable {
      services.greetd = {
        enable = true;
        settings.default_session.command = "${greeterCommand}";
      };
      fonts.packages = gcfg.fonts;
      # The greeter's own directory (its memory of the last user and session) and the users' slots.
      systemd.tmpfiles.settings."10-kurashi-greeter" = {
        ${greeterDir}.d = {
          user = "greeter";
          group = "greeter";
          mode = "0755";
        };
      } // slots;
    })

    (lib.mkIf cfg.webdock.enable {
      environment.systemPackages = [ cfg.webdock.package ];
    })
  ];
}
