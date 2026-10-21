self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kurashi;
  wd = cfg.webdock;
  toml = pkgs.formats.toml { };
  envList = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.extraEnvironment;
  exportsTo = app: cfg.themeExport.includes && lib.elem app cfg.themeExport.apps;

  # Defaults of niri.binds.keys (niri key name -> kurashi action id, see docs/niri-binds.kdl).
  niriDefaultKeys = {
    "Mod+Space" = "launcher.toggle";
    "Mod+N" = "notifications.center";
    # K54: the sidebars (an action with arguments: the id, a space, the JSON).
    "Mod+Shift+N" = ''sidebar.toggle {"side":"right"}'';
    "Mod+A" = ''sidebar.toggle {"side":"left"}'';
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
  # An entry is an action id, or the id, a space and its JSON arguments (`sidebar.toggle {"side":"left"}`).
  niriBindLine =
    key: entry:
    let
      parts = builtins.match "([^ ]+) (.+)" entry;
      action = if parts == null then entry else builtins.elemAt parts 0;
      args = lib.optional (parts != null) (builtins.elemAt parts 1);
      quote = s: "\"${lib.escape [ "\\" "\"" ] s}\"";
      lhs = lib.concatStringsSep " " ([ key ] ++ niriBindProps action);
    in
    "    ${lhs} { spawn ${lib.concatMapStringsSep " " quote ([ "${cfg.package}/bin/kurashi" "act" action ] ++ args)}; }";

  # The web dock's settings are the mod's own keys (K38, K40; mods/webdock/mod.toml), written as `mods.webdock.<key>`
  # into the Nix layer. A null option writes nothing and leaves the mod's default in place.
  webdockSettingKeys = [
    "default_view" "width" "large" "edge" "unload_after" "max_loaded" "hover" "reopen_last"
    "pinned" "reserve" "indicator" "strip" "new_tabs"
  ];
  webdockSetting = type: description: lib.mkOption {
    type = lib.types.nullOr type;
    default = null;
    inherit description;
  };
  webdockPinToml = pin: lib.filterAttrs (_: v: v != null) { inherit (pin) id title target view profile icon; };
  webdockToml =
    lib.filterAttrs (_: v: v != null) (lib.genAttrs webdockSettingKeys (key: wd.${key}))
    // lib.optionalAttrs (wd.pins != [ ]) { pins = map webdockPinToml wd.pins; };

  # kurashid starts the web host and opens links by name (K38: `exec:qs-webengine` and `exec:xdg-open` are looked up
  # in its PATH, which a user manager may not carry). With the dock on, the daemon's PATH starts with the dock
  # package's commands, by store path, as the other units name their tools (KURASHI_QS).
  daemonPackage =
    if wd.enable then
      pkgs.runCommand "kurashid-webdock" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p $out/bin
        makeWrapper ${cfg.package}/bin/kurashid $out/bin/kurashid --prefix PATH : ${lib.makeBinPath [ wd.package ]}
      ''
    else
      cfg.package;
in
{
  options.programs.kurashi = {
    enable = lib.mkEnableOption "Kurashi-shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi;
      description = "Kurashi package (daemon + CLI + frontend data).";
    };

    fonts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ material-symbols nunito inter jetbrains-mono noto-fonts noto-fonts-cjk-sans noto-fonts-cjk-serif quicksand comic-neue cinzel eb-garamond roboto (google-fonts.override { fonts = [ "Kalam" "KleeOne" ]; }) ];
      defaultText = lib.literalExpression "with pkgs; [ material-symbols nunito inter jetbrains-mono noto-fonts noto-fonts-cjk-sans noto-fonts-cjk-serif quicksand comic-neue cinzel eb-garamond roboto (google-fonts.override { fonts = [ \"Kalam\" \"KleeOne\" ]; }) ]";
      description = ''
        Fonts the shell draws with: Material Symbols (Rounded, and Sharp for line chrome) for icons (without it,
        components fall back to text glyphs), the looks' families (K42, K45, K53: Nunito for `sekai`, Inter for
        `glass`, JetBrains Mono for `terminal`, Noto Serif for `washi`; W25: Quicksand and Comic Neue for `kawaii`, Cinzel
        for `hallownest`, EB Garamond for `souls`, Roboto for `material`; K60: Kalam and Klee One for `kami` — the looks' other families are not free and
        fall back along their chains) and Noto CJK (sans and serif) for Japanese.
        Installed with fontconfig enabled; set to [ ] to manage fonts yourself.
      '';
    };

    tools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ wlsunset wf-recorder cava ];
      defaultText = lib.literalExpression "with pkgs; [ wlsunset wf-recorder cava ]";
      description = ''
        Programs kurashid runs (K47), installed with the user's packages (NixOS puts the per-user profile on the
        user manager's PATH): wlsunset for night light, wf-recorder for the screen recorder, cava for the media level bars
        (K48; it runs only while a media view with bars is on screen, and without it the bars are a still mark). gpu-screen-recorder is preferred when it is installed (it needs the NixOS module's
        {option}`programs.kurashi.gpuScreenRecorder.enable` for its capability wrapper). Without a program, the
        quick settings tile says why instead of acting. Idle (dim, lock, screens off, suspend) is the daemon's own:
        no swayidle or hypridle is needed — turn those off, or set `idle.enabled = false`.
      '';
    };

    clipboardHistory = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Keep a clipboard history with cliphist (Home-Manager's services.cliphist), which the launcher shows after `;`.";
    };

    themeExport = {
      apps = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "gtk3" "gtk4" "qt" "qt5" "foot" "kitty" "alacritty" "ghostty" "niri" ]);
        default = [ ];
        example = [ "gtk3" "gtk4" "foot" ];
        description = ''
          Apps that follow the shell's colours (K49, `theme.export`): kurashid writes their colour files whenever the
          theme changes. Set as a Nix value of `theme.export`.
        '';
      };
      includes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Add the line each app needs to read its colour file, through that app's own Home-Manager module when it is
          enabled here (gtk, foot, kitty, alacritty, ghostty). niri and Qt (qt6ct/qt5ct) need it by hand: Settings
          shows the line.
        '';
      };
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
        type = lib.types.attrsOf (lib.types.nullOr (lib.types.strMatching "[a-z0-9._-]+( [{].*[}])?"));
        default = { };
        example = lib.literalExpression ''{ "Mod+L" = "session.lock"; XF86AudioMute = null; }'';
        description = ''
          niri key name to kurashi action id (the argument of `kurashi act`), optionally followed by a
          space and the action's JSON arguments. Entries add to the defaults and override them for the
          same key; `null` removes a default. The defaults:
          `Mod+Space` launcher.toggle, `Mod+N` notifications.center, `Mod+Shift+N` and `Mod+A`
          `sidebar.toggle {"side":"right"}` and `{"side":"left"}`, `Mod+Shift+E` session.menu,
          `Super+Alt+L` session.lock, `XF86AudioRaiseVolume` and `XF86AudioLowerVolume`
          audio.volume.up and audio.volume.down, `XF86AudioMute` audio.mute.toggle,
          `XF86MonBrightnessUp` and `XF86MonBrightnessDown` brightness.up and brightness.down.
          The niri defaults for the same keys are replaced (see docs/niri-binds.kdl).
          The web dock adds its own key, {option}`programs.kurashi.webdock.keybind`.
        '';
      };
    };

    webdock = {
      enable = lib.mkEnableOption "the web dock (K38): its host package, the mod turned on, and the pins and settings below";

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.kurashi-webdock;
        description = ''
          The web dock's package: `qs-webengine` (the patched Quickshell with QtWebEngine, K39) and `xdg-open`.
          It is installed only while {option}`programs.kurashi.webdock.enable` is set, so the base closure
          stays free of QtWebEngine.
        '';
      };

      pins = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.strMatching "[a-z0-9-]{1,32}";
              description = "Slug, unique among the pins.";
            };
            title = lib.mkOption {
              type = lib.types.str;
              description = "The pin's name in the dock.";
            };
            target = lib.mkOption {
              type = lib.types.strMatching "(https?|file)://.+|mod:.+";
              description = "A site (`https://`, `http://` or `file://`), or a view of a mod (`mod:<id>:<panel>`).";
            };
            view = webdockSetting (lib.types.enum [ "default" "mobile" "desktop" ]) "The site's view; `default` (or null) takes {option}`programs.kurashi.webdock.default_view`.";
            profile = webdockSetting lib.types.str "The storage profile: pins with one profile share its logins and view; null takes the pin's id.";
            icon = webdockSetting lib.types.str "The pin's icon; null leaves it empty (the site's favicon, else a letter tile).";
          };
        });
        default = [ ];
        example = lib.literalExpression ''
          [
            { id = "news"; title = "News"; target = "https://example.org/news"; view = "mobile"; }
            { id = "sysmon"; title = "System"; target = "mod:sysmon:panel"; }
          ]
        '';
        description = ''
          The pins, in order (the mod's `pins` records, K38). Settings shows them as set by Home-Manager;
          {option}`programs.kurashi.enforce` makes them forced. Ids must be unique.
        '';
      };

      keybind = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9_+-]+");
        default = "Mod+B";
        description = ''
          Niri key that toggles the dock (`webdock.toggle`, run through `kurashi act`). It is one of the
          {option}`programs.kurashi.niri.binds.keys`, so it is written only while
          {option}`programs.kurashi.niri.binds.enable` is set. `null` adds no bind.
        '';
      };

      default_view = webdockSetting (lib.types.enum [ "mobile" "desktop" ]) "The view of a pin that says `default`: mobile (phone width, mobile user agent) or desktop (mod default: mobile).";
      width = webdockSetting (lib.types.ints.between 360 720) "Phone width in pixels (mod default: 412).";
      large = webdockSetting (lib.types.ints.between 50 95) "The large size, as a percentage of the output's width (mod default: 90).";
      edge = webdockSetting (lib.types.enum [ "right" "left" "top" "bottom" ]) "The screen edge the dock sits at (mod default: right).";
      unload_after = webdockSetting (lib.types.ints.between 0 1440) "Minutes without a shown site before the web engine stops; 0 keeps it running while the dock is on (mod default: 60).";
      max_loaded = webdockSetting (lib.types.ints.between 1 12) "Sites kept loaded at once, the shown one included (mod default: 4).";
      hover = webdockSetting lib.types.bool "Reveal the dock when the pointer rests on its edge; off, only the keybind and the bar button show it (mod default: true).";
      reopen_last = webdockSetting lib.types.bool "A reveal opens the page that was open; clicking its icon puts it away (mod default: true).";
      pinned = webdockSetting lib.types.bool "The strip stays while the pointer is elsewhere (mod default: false).";
      reserve = webdockSetting lib.types.bool "Windows make room for the strip while the dock is kept open; the page card always floats over them (mod default: false).";
      indicator = webdockSetting lib.types.bool "The edge indicator, drawn while the dock is hidden (mod default: true).";
      strip = webdockSetting (lib.types.ints.between 40 64) "Width of the icon strip in pixels (mod default: 56).";
      new_tabs = webdockSetting (lib.types.enum [ "dock" "browser" ]) "Links that open a new tab: into the dock (the link replaces the page, Back returns), or into the default browser (mod default: dock).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # wl-copy: the launcher copies a calculation (K42 session).
      home.packages = [ cfg.package pkgs.wl-clipboard ] ++ cfg.fonts ++ cfg.tools;
      fonts.fontconfig.enable = lib.mkIf (cfg.fonts != [ ]) (lib.mkDefault true);
      services.cliphist.enable = lib.mkIf cfg.clipboardHistory (lib.mkDefault true);

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

      # K49: the apps that follow the theme, as Nix values, and their include lines through their own modules.
      programs.kurashi.settings.theme = lib.mkIf (cfg.themeExport.apps != [ ]) { export = cfg.themeExport.apps; };
      gtk.gtk3.extraCss = lib.mkIf (exportsTo "gtk3" && config.gtk.enable) (lib.mkAfter "@import 'kurashi-colors.css';");
      gtk.gtk4.extraCss = lib.mkIf (exportsTo "gtk4" && config.gtk.enable) (lib.mkAfter "@import 'kurashi-colors.css';");
      programs.foot.settings.main.include = lib.mkIf (exportsTo "foot" && config.programs.foot.enable)
        "${config.xdg.configHome}/foot/kurashi-colors.ini";
      programs.kitty.extraConfig = lib.mkIf (exportsTo "kitty" && config.programs.kitty.enable) (lib.mkAfter "include kurashi-colors.conf");
      programs.alacritty.settings.general.import = lib.mkIf (exportsTo "alacritty" && config.programs.alacritty.enable)
        [ "${config.xdg.configHome}/alacritty/kurashi-colors.toml" ];
      programs.ghostty.settings.theme = lib.mkIf (exportsTo "ghostty" && config.programs.ghostty.enable) (lib.mkDefault "kurashi");

      systemd.user.services.kurashid = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Kurashi shell daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${daemonPackage}/bin/kurashid";
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
    })

    (lib.mkIf wd.enable {
      assertions = [
        {
          assertion = cfg.enable;
          message = "programs.kurashi.webdock.enable needs programs.kurashi.enable = true.";
        }
        {
          assertion = lib.length (lib.unique (map (pin: pin.id) wd.pins)) == lib.length wd.pins;
          message = "programs.kurashi.webdock.pins: each pin id may appear once.";
        }
      ];
      warnings = lib.optional (wd.keybind != null && !cfg.niri.binds.enable) ''
        programs.kurashi.webdock.keybind (${wd.keybind}) writes no bind: binds go to niri/kurashi-binds.kdl,
        which needs programs.kurashi.niri.binds.enable = true (or set keybind to null).
      '';

      home.packages = [ wd.package ];

      # The dock's bind joins the niri binds; a user entry for the same key wins.
      programs.kurashi.niri.binds.keys = lib.mkIf (wd.keybind != null) {
        ${wd.keybind} = lib.mkDefault "webdock.toggle";
      };

      # The mod is loaded and on (K25: enabled is a subset of loaded). Its settings form the Nix layer of
      # `mods.webdock`; lists from other modules of `settings.mods` merge in.
      programs.kurashi.settings.mods = {
        loaded = [ "webdock" ];
        enabled = [ "webdock" ];
        webdock = webdockToml;
      };
    })
  ];
}
