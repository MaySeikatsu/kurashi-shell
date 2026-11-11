# Web dock engine and ad blocking — options for later (session 20)

Why this exists: the user wants uBlock Origin in the web dock "mainly for YouTube". The dock renders pages with
QtWebEngine (K38, K39), and on QtWebEngine 6.11.2 neither uBlock runs (BACKLOG I373, CONTRACT-CHANGE 693). This page
keeps every option found so far, so the engine choice can be reconsidered with the evidence in one place. Nothing here
is decided; it is research for a future K-decision.

## What was measured (session 20)

- **Full uBlock Origin 1.75.2 (Manifest V2):** `extensionManager.loadExtension` → `error = "Unsupported manifest
  version"`. QtWebEngine has no MV2 and no blocking `webRequest` API, which full uBO needs.
- **uBlock Origin Lite 2026.1026.1812 (MV3):** loads and enables, but its service worker fails (`chrome.permissions`
  undefined, status 15) and declarativeNetRequest is not enforced (`getEnabledRulesets()` = `[]`, even for a minimal
  test extension; a decoy URL a uBOL rule matches got HTTP 200). It made no request of its own.
- **YouTube:** its ads come from the same hosts as the video (first-party, server-side). Blocking by host or URL does
  not remove them; uBO removes them with *scriptlets* (it rewrites the player's JSON responses and page globals:
  `json-prune`, `set-constant`, …) and updates those rules often. Any option that only blocks requests fails YouTube.
- **Helium** (the user's browser) runs full uBO because it is a full Chromium-based browser that patches Chromium to keep
  MV2 and `webRequest` blocking. It is a browser, not an embeddable engine.

## Options

### 1. Host a real browser window in the dock (recommended to prototype)

The dock stops rendering pages itself and instead shows a window of the user's own browser in app mode (Helium or any
Chromium: `--app=URL --user-data-dir=<per-pin profile>`; Firefox/Zen: a dedicated profile with a kiosk-like
`userChrome.css`), placed by the compositor where the dock's well is.

- **Pro:** real uBlock (YouTube included, kept current by its maintainers), the user's logins, passkeys, sync and
  extensions; no engine to package (QtWebEngine leaves the closure, K39's size problem goes too); no per-engine
  privacy work of our own.
- **Con:** placement is per compositor — niri: a window rule (`open-floating`, `default-floating-position`, size,
  `block-out-from`) plus IPC to show/hide/move it; Hyprland/Sway/MangoWM: their own rules and IPC. There is no
  Wayland protocol for a shell to embed another client's surface, so the window is beside the shell, not inside it:
  the dock draws its chrome (strip, header) around a hole the window sits in, and stacking/focus/animation must be
  matched to the compositor (the window cannot share the shell's blur sheet or join it seamlessly).
- **The user picks the engine (user, session 20):** the dock's browser becomes a setting — "the default browser" or a
  named one (Helium, Chromium, Brave, Firefox, Zen, …), per dock or per pin — so the dock runs independent of an engine
  we ship and maintain. A small launch recipe per browser family (Chromium: `--app=URL --user-data-dir=…`
  `--class=<pin>`; Gecko: `--new-instance --profile <dir> --kiosk URL` or `--name`) gives each pin its window, its own
  profile and an app id the compositor rules match. kurashi keeps only the dock's chrome, placement and lifecycle; the
  engine, its extensions (uBlock), updates and privacy are the user's browser's. QtWebEngine could stay as an optional
  built-in for users without a fitting browser, or go.
- **Ma (rule 5):** hidden = the browser window is hidden or closed; the daemon owns start/stop and the idle timeout as it
  does for the web host now (K40).
- **Shōjiki:** the dock says which browser runs a pin and that the page is that browser's (its settings apply).
- **Generalisation (user, session 20):** if it works it is a general feature — *shell-hosted windows*: any app window
  docked into a shell surface. A terminal in a sidebar or a drop-down, Anki in the left sidebar, a music player, a
  notes app. See BACKLOG "Shell-hosted app windows". The dock would be its first user.

### 2. A different embedded engine

- **CEF (Chromium Embedded Framework):** closest to Chrome; its Chrome-style runtime runs Chrome extensions, but MV2 and
  blocking `webRequest` are being removed upstream as in Chrome, so full uBO would need Helium-style patches of our own
  to Chromium (a large, ongoing maintenance cost). Not a Qt/QML engine: a new host process and its own GPU/input path.
- **WebKitGTK / WPE:** no WebExtension support usable for uBO; content blockers (WebKit's JSON rule format) block
  requests only — the YouTube problem remains.
- **Gecko:** full uBO works in Firefox, but there is no maintained desktop embedding API (GeckoView is Android only).
- **Servo:** no extensions.
- **Patch QtWebEngine to keep MV2/webRequest:** QtWebEngine implements only a small part of the extension APIs; adding
  blocking `webRequest` and the rest uBO needs is Chromium-browser-layer work, not a small patch.

### 3. Stay on QtWebEngine and imitate uBlock

- **Network blocking** with `QWebEngineUrlRequestInterceptor` (C++, `QQuickWebEngineProfile::setUrlRequestInterceptor`;
  a small type in `nix/patches/quickshell-webengine.patch`) and a pinned filter list.
- **Cosmetic and scriptlet filtering** with Brave's `adblock-rust` (parses uBO/EasyList lists, network rules, cosmetic
  selectors, scriptlet injections per URL) and QtWebEngine's user scripts (`WebEngineScript`, document-creation, main
  world) to inject uBO's YouTube scriptlets and hiding CSS.
- **Pro:** stays in the current architecture; works per pin; no window placement problem.
- **Con:** we own the arms race with YouTube (uBO's scriptlets change weekly; the lists would need regular updates —
  which itself means network traffic the privacy rules must allow and say); `adblock-rust` must be built into the host
  (C FFI into the Quickshell patch); no element picker / per-site toggles UI unless we build it.

### 4. Network-only blocker (dropped for YouTube)

The interceptor alone with a hosts-style list (BACKLOG I376, dropped). Blocks ads and trackers on most sites, does
nothing for YouTube. Kept only as a possible first step of option 3.

## Next step when this is picked up

Prototype option 1 on niri: one pin as a Helium `--app` window with a niri window rule and `niri msg` IPC for
show/hide/move, measured against the dock's states (hidden, shown, large, the four edges, multi-output) and the budget
(BENCH). If placement and focus feel right, write the K-decision for shell-hosted windows and the dock's move to it;
if not, option 3.

## The engine's lifecycle, measured (W73, session 29)

QtWebEngine 6.11 (`qs-webengine`), headless sway sandbox, Chromium's fake audio output (no sound server: the ALSA open
fails with "Host is down", and the engine still reports the sound), `mods/webdock/test/pages/tone.html`:

- **`recommendedState` is re-evaluated on the view's own events** (shown or hidden, a load, a lifecycle change), not when
  the sound stops. A page hidden while it plays stays `Active` through the silence that follows (its recommendation is not
  revisited), so its next track starts — measured with a new `<audio>` per track, one `<audio>` with a new source,
  WebAudio, and with `history.pushState` per track.
- **A page hidden in a silence** (the gap between tracks, a pause, the second before the first sound) is recommended
  `Frozen` at once, then `Discarded`; a host that follows the recommendation freezes it, and a frozen page never runs the
  timer that starts its next track. That is the freeze `WebPage.qml` followed before W73 (test-background.sh "gap": fails
  on the old file, passes on the new one).
- **The engine's own audible hold** after the last sound is short: in the logs `recentlyAudible` falls right after the
  page logs its track's end (not timed more exactly) — far shorter than any pause.
- **Autoplay:** a page that had one click may start new `<audio>` elements from a timer later, hidden or not
  (`playbackRequiresUserGesture` default): autoplay is not what stops a player here.
- **Timers of a hidden page** run about once a second (Chromium's background throttling): a ticking page logged 5 ticks
  in 6 s while hidden and `Active`.
