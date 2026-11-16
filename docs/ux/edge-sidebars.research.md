# Edge panels and quick-settings modules: how other shells do it

Research for the kurashi-shell UX briefs. Method: web search and page fetches only, no installs, no clones. Research date 2026-11-16.

Conventions:
- Each bullet ends with the URL it came from.
- "Not found" means I could not confirm the point from a page I could open.
- "(snippet)" means the fact came only from a search result; "(not opened)" means the URL was seen in results but not fetched.
- "My reading" or "my inference" marks my own interpretation of a source.
- Several upstream READMEs (ddterm, Dash to Panel, Guake, HyprPanel, Noctalia, DankMaterialShell, end-4) carry no placement or size facts. Where that happened, the docs site, a source file or an issue thread is cited instead.
- Versions differ. Where a source names its version or date, that is given.

---

## Question 1: panels and drawers on the top and bottom edges

### GNOME Shell (top bar)
- Top-bar items: Activities (top left), the clock (opens calendar, appointments and notifications) and the system menu (top right). https://help.gnome.org/gnome-help/shell-introduction.html
- Quick Settings is a menu of toggles and sub-menus. The help does not say where it opens, its width, or how it closes. https://help.gnome.org/gnome-help/quick-settings.html
- Not found (help pages and the GNOME 43 notes): drop-down from the top bar, width, height, closing, pinning, multi-monitor, keyboard. The 43 notes describe only a "redesigned system status menu". https://release.gnome.org/43/
- Extension API: Quick Settings is "a user-interface pattern for the GNOME Shell System Menu", documented for GNOME 45 and later. https://gjs.guide/extensions/topics/quick-settings.html

### GNOME: Dash to Panel (extension 1160)
- Extension page: "An icon taskbar for the Gnome Shell"; "moves the dash into the gnome main panel"; "the application launchers and system tray are combined into a single panel". https://extensions.gnome.org/extension/1160/dash-to-panel/
- Top or bottom only, per a Gitee mirror of the README (not checked against GitHub): "Set main panel position (top or bottom) and height"; its FAQ says "I don't think it is possible to allow for a vertical layout." https://gitee.com/ALEX_233/dash-to-panel
- The upstream GitHub README I fetched lists no edges, length options or multi-monitor behaviour. Its wiki page "Enable and Customize" did not load. https://github.com/home-sweet-gnome/dash-to-panel and https://github.com/home-sweet-gnome/dash-to-panel/wiki/Enable-and-Customize
- Conflict: a LinuxToday headline says "Dash to Panel v24 released with vertical panel orientation update" (snippet; article blocked with HTTP 403). https://www.linuxtoday.com/infrastructure/dash-to-panel-v24-released-with-vertical-panel-orientation-update-from-github-feature
- The GitHub releases page I could open lists only v63 to v74, with no vertical-orientation entry, so the conflict is unresolved. https://github.com/home-sweet-gnome/dash-to-panel/releases
- Mirror README: the extension "manipulates the Gnome Main Panel, aka Top Bar" (so it modifies the bar rather than adding one; my inference). https://gitee.com/ALEX_233/dash-to-panel
- Not found: length (full or fit), height values, pinning, multi-monitor, auto-hide triggers.

### GNOME: ddterm (drop-down terminal)
- Upstream README: "drop down terminal", "With tabs", "Can be controlled from the command line". It names no edge, size, monitor or focus rule. https://github.com/ddterm/gnome-shell-extension-ddterm
- PR #889 (opened 15 Apr 2024, closed unmerged 5 Mar 2026): "previously, only one was configurable - depending on your window orientation"; "For now, the window position is always centered". https://github.com/ddterm/gnome-shell-extension-ddterm/pull/889
- Issue #129 (closed 10 Jun 2026): the width request became adjustable side spacers, which the maintainer said was "implemented in v63.2.0". On 28 Aug 2026: "One of the window's dimensions still takes full screen size." Height is not addressed; centring was reported as off on 16 Aug 2026. https://github.com/ddterm/gnome-shell-extension-ddterm/issues/129
- Extension page lists "With tabs" and the Shell versions only. https://extensions.gnome.org/extension/3780/ddterm/
- Not found: monitor selection, hotkey, animation, keep-open or hide-on-focus-loss in the README or the extension page.

### KDE Plasma 6 (panels)
- "Dodge Windows" (aka Intelligent auto-hide / Intellihide) is a panel visibility mode "replacing the old 'Windows Can Cover' mode" (Plasma 6.0). https://community.kde.org/Plasma/Plasma_6
- Plasma 6.0 default change: "Use Floating panel by default". Panel settings are "exposed in a much nicer way". Plasma 6.3: "Clone a panel". https://community.kde.org/Plasma/Plasma_6
- User reaction (May 2024 to Mar 2025, no developer reply): "The loss of the panel option to 'Allow windows to cover' is an annoyance"; "The 'Dodge Windows' and 'Auto-hide' behaviours are no substitute." https://discuss.kde.org/t/windows-can-cover-panel-can-we-have-it-back-in-plasma-6/15706
- Multi-monitor: bug 488290 (Plasma 6.0.5) says dodge and auto-hide fail for panels on inner screen edges in multi-monitor setups (snippet). https://bugs.kde.org/show_bug.cgi?id=488290
- Bug 515057 (6.6 beta) reports docked panels in Dodge Windows mode as broken, status Needs Info; its example config has "Width: fill width" (snippet). https://bugs.kde.org/show_bug.cgi?id=515057
- Handbook panel page: no edge, width, height or visibility option is named. The revision may predate Plasma 6. https://docs.kde.org/stable_kf6/en/plasma-desktop/plasma-desktop/panel.html
- Not found in any official source: fit-content, fill and custom width as named options. Plasma 6.7: "Support different panel positions with Oxygen Plasma style" suggests edge choice depends on the style (not confirmed). https://community.kde.org/Plasma/Plasma_6
- Keyboard: a Planet KDE post covers showing and hiding a panel from the keyboard, with the shortcut set in the panel's settings (snippet, not opened). https://planet.kde.org/nathan-upchurch-2024-03-18-setting-up-a-toggleable-side-panel-in-kde-plasma-6

### KDE: Yakuake (drop-down terminal)
- Schema defaults (KDE source file): Width 90 % (range 10 to 100); Height 50 % (range 10 to 100); "Screen" 0 means the screen holding the mouse pointer. https://lxr.kde.org/source/utilities/yakuake/app/config/yakuake.kcfg
- Same file: KeepOpen true (stays open when focus leaves); FocusFollowsMouse false; ToggleToFocus false (the toggle key does not focus an open window); KeepOpenAfterLastSessionCloses false; UseWMAssist true (window manager does the animation); Frames 17 (range 0 to 50, open and retract animation). https://lxr.kde.org/source/utilities/yakuake/app/config/yakuake.kcfg
- No Yakuake handbook page for these settings found. A bug report on scaling-related height errors (snippet). https://bugs.kde.org/show_bug.cgi?id=388217

### COSMIC (System76)
- "COSMIC supports single- and dual-panel layouts, with panels on any screen edge." Applets sit at the beginning, centre or end of a panel. https://system76.com/cosmic/ux
- A December 2025 review: the panel and dock "can be made larger or smaller, moved to the sides of the screen, set to automatically hide"; "The dock can be disabled entirely". https://lwn.net/Articles/1050268/
- Extend to edges (design issue, opened 9 May 2023, closed as completed 29 Sep 2023): with "Extend panel to screen edges" off, the panel "shrinks in width and hugs the content, which will be centered"; "Gap and Extend can be independently toggled". https://github.com/pop-os/cosmic-epoch/issues/102
- Corner rule in the same issue: with gap on, sides that meet a screen edge get 8 px of padding; with gap off, corners at the screen boundary are square. https://github.com/pop-os/cosmic-epoch/issues/102
- Not found: floating or island mode in current docs (the 2025 review says "Not stated"), applet popups, pinning or reserved space, multi-monitor, keyboard. https://lwn.net/Articles/1050268/

### macOS
- Control Center opens by clicking its menu-bar icon: "A panel opens, showing all the controls at the same time." Position alt text: "Control Center in the top-right portion of the screen". Width, height and drop-down behaviour: not stated. https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac
- Notification Center: "Click the date or time at the top right of the screen, or swipe left from the right edge of the trackpad with two fingers." Width, edge, pinning and closing: not stated. https://support.apple.com/en-am/guide/imac/apd6d7eb47b9/2023/mac/14
- Not found: keyboard shortcut, hover opening, Escape or click-outside closing, multi-monitor behaviour. https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac

### Windows 11
- Widgets board opens from the taskbar Widgets area, Win+W, or "Swiping from the side of the screen". Edge, width and closing are not stated. An "Open Widgets board on hover" setting exists. https://support.microsoft.com/topic/7ba79aaa-dac6-4687-b460-ad16a06be6e4
- Quick Settings flyout is "available through the Taskbar (in the System Tray)"; Win+A opens it (third-party guide, Jan 2023). No Microsoft page found. https://pureinfotech.com/change-quick-settings-buttons-windows-11/
- Notification Center: no Microsoft page or fetched source found.
- Taskbar position: a Pureinfotech article (dated 20 Aug 2026, updated 30 Oct 2026) says a September 2026 update restores top, left, right and bottom taskbar positions for 25H2 and later. It cites no Microsoft source and gives two different Windows versions. https://pureinfotech.com/windows-11-move-taskbar-position-top-left-right-bottom/
- Same article, on WindHawk's top-taskbar extension: "the Start menu will continue to open from the bottom up, and Notification Center will stay at the bottom." https://pureinfotech.com/windows-11-move-taskbar-position-top-left-right-bottom/

### Caelestia shell (caelestia-dots/shell, Quickshell)
- Code, top and bottom: the dashboard is anchored to the top edge and centred ("anchors.top: parent.top", "anchors.horizontalCenter"); the launcher to the bottom edge, centred. https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Panels.qml
- Code, sides and corners: session on the right edge, vertically centred; sidebar on the right edge between notifications (top-right corner) and utilities (bottom-right corner); OSD on the right edge; toasts on the right side, left of the sidebar. Popout position: not shown. https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Panels.qml
- Sizes: not shown in Panels.qml (child components set them). The README documents no size or edge keys for the drawers. https://github.com/caelestia-dots/shell
- Open (Interactions.qml): the dashboard opens on hover into the top zone (gated by dashboard.showOnHover) or by dragging down past dashboard.dragThreshold. The launcher opens on hover into the bottom zone, or by dragging up when its gate is off. Utilities open on hover at the bottom. Session opens by dragging left. The sidebar opens by hovering the top-right trigger, or by dragging left while hidden. https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Interactions.qml
- Close: pointer leaves the zone, unless a shortcut opened the panel. Click-outside and Escape: not shown. https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Interactions.qml
- Reserved space (Exclusions.qml): one exclusion window per edge. The left one uses the bar's exclusiveZone; the other three default to the border thickness. My reading: the frame border is reserved, not the drawers (runtime effect not checked). https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Exclusions.qml
- Multi-monitor: one instance per screen (Variants over Screens.screens); per-monitor config at ~/.config/caelestia/monitors/<name>/shell.json; "Not all options respect per-monitor overrides." https://github.com/caelestia-dots/shell/blob/main/modules/drawers/Drawers.qml and https://github.com/caelestia-dots/shell
- Keyboard: "All keybinds are accessible via Hyprland global shortcuts."; the IPC list comes from `caelestia shell -s`. https://github.com/caelestia-dots/shell

### end-4 illogical-impulse (dots-hyprland)
- README: the Quickshell widget system is "used for the status bar, sidebars, etc."; Super+/ is the keybind list; the overview "Shows open apps with live previews". https://github.com/end-4/dots-hyprland
- Module folders under ii: bar, cheatsheet, dock, overview, sidebarLeft, sidebarRight, verticalBar, notificationPopup and others. Names only; no edges. https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii
- The dock folder's file names carry no position (Dock.qml, DockApps.qml and others). https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/dock
- Not found: which edge the bar, dock or overview use; sizes; pinning; reserved space; closing; multi-monitor. The wiki redirects to ii.clsty.link, and the only page I could open was the Quickshell setup page. https://ii.clsty.link/en/ii-qs/01setup/ (redirect host, not verified as the project's own)

### DankMaterialShell (DMS; docs now at duxlabs.dev)
- Docs: version 2.1 (stable) at duxlabs.dev. The old danklinux.com docs redirect there (301). https://duxlabs.dev/docs
- Popouts: "Popup panels triggered by bar widgets, such as the control center, app drawer, and notification center."; "These are anchored to the bar and slide out accordingly." https://duxlabs.dev/docs/dms/layers
- Namespaces: "Dash" (DankDash) dms:dash; control center dms:control-center; notification popout dms:notification-center-popout; process list dms:process-list-popout. The page says the bar can sit at the "top, bottom, left, or right edge". https://duxlabs.dev/docs/dms/layers
- Not found: DankDash or popout width, height, closing, pinning, reserved space, multi-monitor. The GitHub URL showed a page whose README is titled dux-shell, so the project may have moved (not verified). https://github.com/AvengeMedia/DankMaterialShell
- Release note snippet: v1.4.1 "changed how height-varying popouts are positioned against the top and bottom edges" (snippet, not opened). https://newreleases.io/project/github/AvengeMedia/DankMaterialShell/release/v1.4.1

### Noctalia shell
- Control Center opens from its bar widget, by right-clicking empty bar space, or by IPC. Width defaults to 700 px (range 600 to 1200) in the full-sidebar layout. https://docs.noctalia.dev/noctalia/v5.4.1/control-center/
- Height: "No height key appears for any panel." https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Each panel is "attached" or "floating". Control Center defaults to attached, position "auto". Attached panels "get a layer surface of their own", sit "against the host bar's inward edge", and "stay borderless on the bar edge". https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Floating panels keep `floating_offset` (default 8 px) from the bar edge. Position keys such as center or top_left fix a floating panel to a screen spot. For attached panels they move the panel along a bottom or right bar. https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Open near click: `open_near_click_control_center` (default false) opens the panel beside the clicked widget. IPC and shortcuts use the position setting. https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Two bars on one edge: "exact source-bar attachment is ambiguous"; `panel_anchor_bar` fixes it "at the cost of attaching every panel to that bar." https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Layer: `floating_layer` is overlay (default) or top; overlay "keeps these panels above fullscreen content". https://docs.noctalia.dev/noctalia/v5.4.1/configuration/shell/
- Closing (click outside, Escape) and reserved space: not stated. Keyboard: tab_next and tab_previous move focus between the sidebar and the tab content; arrow keys move within the focused pane. https://docs.noctalia.dev/noctalia/v5.4.1/control-center/
- Compositors named in the README: Niri, Hyprland, Sway, Scroll, Mango, Labwc, dwl. https://github.com/noctalia-dev/noctalia-shell

### HyprPanel
- Repo banner: "This repository was archived by the owner on Apr 27, 2026. It is now read-only."; README: "HyprPanel is in maintenance mode." and "Active development has moved to Wayle." https://github.com/Jas-SinghFSU/HyprPanel
- Drop-down menus: not found. The README names no menu, and gives no placement, size or closing behaviour. https://github.com/Jas-SinghFSU/HyprPanel

### Drop-down terminals as a pattern (Yakuake, Guake, ddterm)
- Guake docs: "Multi-monitor support (open on a specified monitor, open on mouse monitor)"; the window "disappears once you are done by pressing a predefined hotkey (F12 by default)". https://guake.readthedocs.io/en/latest/
- Guake 0.4.4 GConf schema (old; current keys may differ): window_height default 50 (percent of screen vertically); window_width default 100 (percent horizontally); window_losefocus default false (hide on focus loss); show_hide default F12. Animation: not found. https://sources.debian.org/src/guake/0.4.4-1/data/guake.schemas
- Yakuake and ddterm: see the sections above.

---

## Question 1: patterns worth copying and mistakes to avoid (my judgement)

1. Model every edge surface as one anchored type with an edge (top, bottom, left, right) and a width mode (full, centred fraction, fit). Caelestia and DMS both anchor drawers to the bar; a separate geometry per surface is where edge bugs come from.
2. Offer attached (flush with the bar edge, borderless, sharing its corners) and floating (a gap from the edge) as one setting. Noctalia's split and its 8 px floating offset are a sound default.
3. Make hover-at-the-edge opening opt-in and per surface. Caelestia gates it per drawer (showOnHover) and adds drag thresholds; its defaults are mixed (dashboard on, launcher off).
4. State reserved space per surface and per edge in the UI. Caelestia reserves on all four edges but takes the bar's value only on the left; that asymmetry is easy to get wrong.
5. Keep a visible slice when a surface auto-hides. KDE forum users asked for the clock and tray to stay visible with a tiled window, and one proposed an always-visible collapsed strip.
6. Do not ship a duplicate-panel workaround as the design. A KDE forum user called stacking a second panel "incredibly clunky"; one surface with a collapsed state is the cleaner answer.
7. Set the monitor rule in one place and show it. Yakuake uses the screen with the pointer; Guake offers a fixed monitor or the mouse's monitor; Noctalia flags shared edges as ambiguous and fixes them with an anchor bar.
8. Expose focus-loss behaviour as a visible toggle with one stated default. Yakuake keeps the window open by default; Guake hides on focus loss only if enabled. Most shells do not document Escape or click-outside, so state it.
9. Test width and height on the real window manager before promising them. ddterm's width request ended as side spacers because the window still fills one dimension. Check niri and sway, not only a mock.
10. Treat READMEs as a starting point. Most of the READMEs checked (ddterm, Dash to Panel, Guake, HyprPanel, Noctalia, DankMaterialShell, end-4) hold no placement or size facts; the docs site or source file did.

---

## Question 2: quick-settings and control-centre items as bar modules

### GNOME Shell
- Quick Settings is one menu. Its Wi-Fi, Wired, Bluetooth and Power Mode buttons "show status"; sub-menus open via a right-arrow icon. Night Light, Dark Style, Airplane Mode and Keyboard backlight appear "where available". https://help.gnome.org/gnome-help/quick-settings.html
- Single items on the top bar, edit mode or reordering by users: not found. https://help.gnome.org/gnome-help/quick-settings.html and https://release.gnome.org/43/
- Extensions: an indicator icon, toggles, sliders (spanning two columns) and action buttons can be added. The developer's `addExternalIndicator` call sets the placement. https://gjs.guide/extensions/topics/quick-settings.html
- Rest appearance, hover, scroll: not found. https://help.gnome.org/gnome-help/quick-settings.html

### KDE Plasma 6
- Plasma 6.4: "App-provided System Tray icons can be individually hidden." Plasma 6.6: "Pin buttons for the Web Browser and Audio Volume widget when placed standalone on a panel." https://community.kde.org/Plasma/Plasma_6
- Tray visibility is set in the tray's settings dialog, "where you can set entries to display and their visibility". The handbook does not name the choices. https://docs.kde.org/stable_kf6/en/plasma-desktop/plasma-desktop/panel.html
- Visibility labels come from bug reports, not official docs: "Always show all entries" (bug 511816) and "Always hidden" versus "Disabled" (bug 509419). Snippets, not opened. https://bugs.kde.org/show_bug.cgi?id=511816
- Rest, hover, click and scroll for a standalone volume widget, and any item limit: not found. https://community.kde.org/Plasma/Plasma_6

### COSMIC
- "All of the features on the panel and dock are implemented as applets that can be moved around or turned off." https://lwn.net/Articles/1050268/
- Default panel applets cover volume, Bluetooth, accessibility, Wi-Fi, power, graphics and session actions. Whether each is its own popup is not confirmed. The article's captions reference Pop!_OS 24.04. https://system76.com/support/pop-basics
- Layout is the user's choice: "You decide what applets they see on first install and where they're positioned." https://system76.com/cosmic/ux
- Editing: COSMIC Settings, then Desktop, then Panel, "to customize the behavior, style, and placement of applets". https://system76.com/support/pop-basics
- Limit: "At the moment, the applets themselves have no configuration options." https://lwn.net/Articles/1050268/
- Click (beyond the tiling icon, which opens tiling settings), rest appearance, hover, scroll, and maximum applet count: not found. https://system76.com/support/pop-basics

### macOS Control Center
- Per module: "use the dropdown menu next to each module to select 'Show in Menu Bar.'" A placement preview shows "where the control will appear in the menu bar." https://support.apple.com/guide/imac/apd05c5d0c8b/2022/mac/13
- Pinning: Control-click and "Add to Menu Bar", or drag a favourite to the menu bar. Removal: hold Command and drag it off. https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac
- Edit mode: "choose Edit Controls at the bottom of the panel"; drag controls in or out, reorder them, resize some by Control-clicking; "Click Done when you're finished." https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac
- Limit: "Some items can't be added to or removed from Control Center or the menu bar." Which items: not stated. https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac
- Behaviour: click an icon "to toggle a feature on or off"; click the arrow "to reveal more detailed options"; drag a slider for volume or brightness. Rest appearance, hover and scroll: not stated. https://support.apple.com/guide/mac-help/mchlc9d0e1f2/mac

### Windows 11
- Tile editing (January 2023 guide, no version named): a pencil icon "in the bottom-right corner"; "Click the Add button and select the actions button"; "Click the unpin button to remove"; "Click and drag an action button to rearrange it." https://pureinfotech.com/change-quick-settings-buttons-windows-11/
- Per-tile modules on the taskbar: not found. The taskbar shows tray icons that open one flyout. No Microsoft page for Quick Settings found. https://support.microsoft.com/topic/7ba79aaa-dac6-4687-b460-ad16a06be6e4
- Conflicting third-party reports (search results, not opened): one guide says Microsoft removed tile editing from 24H2; others say group policy can switch editing off. https://geekrewind.com/how-to-disable-editing-quick-settings-in-windows-11/ and https://www.digitalcitizen.life/windows-11-quick-settings-no-edit-button-issue-whats-going-on-and-how-to-fix-it/

### Caelestia
- Bar status icons are separate modules with `enabled` switches: lockStatus, network, bluetooth and battery on; audio, microphone and kbLayout off. There is no volume or brightness icon ID. https://github.com/caelestia-dots/shell
- Scroll: `bar.scrollActions` covers workspaces, volume and brightness (all true in the example). What each does is not stated. https://github.com/caelestia-dots/shell
- Quick toggles (wifi, bluetooth, mic, settings, gameMode and dnd on; vpn off) sit in the utilities drawer, not on the bar. https://github.com/caelestia-dots/shell
- Popout contents for activeWindow, tray and statusIcons, click behaviour, rest appearance, edit mode and whether list order sets position: not stated. https://github.com/caelestia-dots/shell

### end-4 illogical-impulse
- Quick toggles on the bar, and how they are configured: not found. The README lists only "screen translation, anti-flashbang, Google Lens" as features. https://github.com/end-4/dots-hyprland

### DankMaterialShell
- The control centre covers "network, Bluetooth, audio devices, display settings, and night mode". https://github.com/AvengeMedia/DankMaterialShell
- Control-centre items as separate bar widgets, edit mode, and their rest or hover behaviour: not found in the 2.1 docs pages I could open. The popouts "triggered by bar widgets" are the control centre, app drawer and notification centre. https://duxlabs.dev/docs/dms/layers
- Tray icons can be hidden by ID with `DMS_HIDE_TRAYIDS` ("Comma-separated list of system tray icon IDs to hide from the system tray bar."). https://duxlabs.dev/docs/dms/advanced-configuration

### Noctalia
- Built-in widgets: volume ("Shows and controls PipeWire output or input volume"), brightness ("Shows the current monitor brightness level and adjusts it via scroll wheel"), network ("Shows Wi-Fi, wired, and VPN status through NetworkManager"), media ("Shows artwork and track details from the active MPRIS player"). https://docs.noctalia.dev/noctalia/bar/widgets/
- Peek (off by default): the value slides out on hover and collapses on leaving. `peek_delay_ms` defaults to 100 (range 0 to 2000); the reveal animates in 200 ms and collapse is immediate. https://docs.noctalia.dev/noctalia/bar/widgets/
- Brightness: "Click opens the display tab in the control center."; the widget hides itself when no controllable monitor is found, unless `show_when_unavailable` keeps a muted icon. https://docs.noctalia.dev/noctalia/bar/widgets/brightness/
- Volume, network and media open the Control Center on the tab set by `sidebar_section`. https://docs.noctalia.dev/noctalia/v5.4.1/control-center/
- Gestures: left, right, middle, back, forward, and scroll in four directions. "middle" opens the widget's settings on every widget; right-click on empty bar space opens the Control Center. https://docs.noctalia.dev/noctalia/bar/actions/
- Scroll repeat defaults to "auto": volume and brightness "run for every step"; cycle commands such as workspaces run "once per gesture". Wheel input is quantised into detents. The 10 % volume step appears only in example bindings. https://docs.noctalia.dev/noctalia/bar/actions/
- Adding: widget names go in a bar's list, `enabled` hides one, and several copies of one type are allowed. Reordering and removal from the list: not stated. https://docs.noctalia.dev/noctalia/bar/widgets/
- Tabs: `hidden_tabs` is "Editable from Settings → Control Center"; "The Home tab cannot be hidden." https://docs.noctalia.dev/noctalia/v5.4.1/control-center/

### HyprPanel
- Archived (see Question 1). Module placement, rest, hover, click and scroll: not found. https://github.com/Jas-SinghFSU/HyprPanel

---

## Question 2: patterns worth copying and mistakes to avoid (my judgement)

1. Put the value behind hover, not at rest. Noctalia's peek shows only the icon until hover; the reveal delay and the collapse timing are settings. That keeps a busy bar quiet.
2. One click, one meaning. Noctalia opens the matching Control Center tab on click; macOS toggles on the icon and reveals detail through the arrow. Keep "toggle" and "open the centre" on different targets.
3. Match scroll to the control. Ramp controls (volume, brightness) step on every detent; cycle controls (workspaces) step once per gesture, as Noctalia's `scroll_repeat` "auto" does.
4. Hide what cannot work, and say why. Noctalia's brightness widget hides when there is no controllable monitor unless told to show a muted icon. This is the honesty rule in practice.
5. Give bar modules stable IDs and enable flags, as Caelestia does, and validate them against the schema. Document whether list order sets position; Caelestia's docs do not say.
6. Offer a per-item pin and a plain list. Plasma 6.6 adds pin buttons to standalone Audio Volume and Web Browser widgets, and COSMIC applets can move or turn off. macOS and Windows edit modes are pointer-driven, so keep a settings list for keyboard users.
7. Keep the first tab non-hideable and say so. Noctalia's "Home tab cannot be hidden" avoids an empty centre.
8. A policy can lock editing (Windows third-party reports). Show the lock and its source, as the provenance field `forced_by` allows, instead of greying the control silently.
9. Do not build a second set of popovers that can drift from the centre. A module and its centre tile should call the same component.
10. Few shells document limits. Plan an explicit cap or paging in the schema so the settings page can show it, and do not rely on undocumented behaviour.

---

## Not confirmed (summary)

- end-4 illogical-impulse: the wiki is reachable only at its setup page; the README and folder names carry no placement or behaviour.
- HyprPanel: the repository is archived; the README holds no behaviour; the wiki was not fetched.
- DankMaterialShell: DankDash size, closing, pinning and bar-widget placement are not in the 2.1 docs pages I could open.
- GNOME Shell: no source found for the top-bar drop-down, its width, or how it closes.
- KDE Plasma 6: fit, fill and custom width options and the tray visibility labels have no official source; the handbook names neither.
- COSMIC: extend and floating modes in the current release rest only on a 2023 design issue; applet popups not found.
- Windows 11: no Microsoft page for Quick Settings, Notification Center or flyout edges; the taskbar-position article cites no source.
- Dash to Panel: the top or bottom versus vertical-orientation conflict is unresolved.
- ddterm: released width and height behaviour is not verified; monitor selection, hotkey and animation not found.
- Guake: current sizes and focus-loss keys are not in the current docs; the only schema found is from 0.4.4.
