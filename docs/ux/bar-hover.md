# Open on hover — UX brief (session 27, I457, I458, K113)
Status: v1. Test `frontend/test-bar-hover.sh`. Prototyped in QML on the user's live niri session, then built.

## Job
Rest the pointer on a bar module and see more of it without a click: its preview, its card, or its menu. One choice for
the whole bar, and a module may take its own. Whatever a hover shows grows out of the bar as one sheet with it.

## How others do it
- **Caelestia** (`modules/bar/popouts`): hovering a status icon opens its popout, joined to the bar; it follows the
  pointer along the bar and closes when the pointer leaves bar and popout. The model for this feature (user).
- **Noctalia**, **DankMaterialShell**, **end-4**, **HyprPanel**: click opens; hover gives a tooltip. HyprPanel has no
  hover-open; Noctalia has "open on hover" for its bar widgets' panels as a setting.
- **KDE Plasma**: hover gives a tooltip or live window thumbnails; panels' applets open on click. **Windows 11**: hover
  thumbnails on the taskbar, widgets board opens on hover (a setting, much disliked when it cannot be turned off).
- **GNOME**, **macOS**, **COSMIC**: click only.
Taken: Caelestia's behaviour as an option, never the only way (Windows' lesson): off by default, a click always works.

## The setting
`bar.hover`: **Preview** (default: the small peek, as before) · **Card** (the module's card; a module without one shows
its preview) · **Menu** (the module's own menu, as a right click). A module's own choice: `bar.hover_preview`,
`bar.hover_card`, `bar.hover_menu` (lists of modules), set from each module's menu: **On hover ▸ As the bar · Preview ·
Card · Menu**. Settings › Layout › Bar has the four rows.
Cards a hover can open: a mod's panel, the clock's face, quick settings, the launcher. Workspaces, windows, the island,
the tray, volume, keyboard and the recorder have no card: under Card they keep their preview. Sidebar buttons stay
click only (a sidebar is not closed by `ui.close`; I465).

## Behaviour
- Intent 220 ms on the module, then it opens. It stays while the pointer is on the module or on what opened; it closes
  380 ms after the pointer has left both (the grace lets the pointer cross the join). Timings judged by the user live.
- Another module's hover replaces what a hover opened. What a **click** opened is never closed or replaced by a hover.
- A press in the card or menu, or typing in the launcher, makes it the user's: it then stays until closed as usual.
- Esc and a click elsewhere close it as before. Under a polkit dialog nothing opens (the daemon refuses).
- No peek is asked for while a card or menu is open.

## The join (I457)
On a top or bottom bar every peek — a window's or workspace's preview, the island's, a tray item's, a mod's — grows out
of the bar and joins it with the cards' fillet (`Theme.rJoin`), in looks with a tooltip part too; in dynamic it runs
into a frame corner it is near (K98). The look's balloon stays beside a side bar and with the springs off.

## States
Empty (a peek with nothing to say draws nothing, I259) · loading (a preview "Not seen yet") · error (a mod without a
panel: its preview) · offline (n/a) · parked in the bar's overflow (no hover there: its card shows the module itself).

## Keyboard and a11y
Hover adds nothing a keyboard lacks: focus shows the preview at once, Enter opens the card, Menu the menu (module-menu.md).
The setting is honest: a module whose mode does nothing for it (Card without a card) says so by showing its preview.

## Motion, multi-output, budget
The card's and the peek's own motion; nothing new. Per output as the cards are. Ma: one HoverHandler per module, enabled
only while its mode is not Preview; the intent and grace timers run only during a hover; idle draws nothing.

## Definition of done
- [x] Setting, lists, module menu row; i18n en/ja; schema goldens.
- [x] `frontend/test-bar-hover.sh`: default opens nothing; card opens, stays, closes; press keeps; click-opened stays;
  a module's own choice; no QML error.
- [x] Seen on the user's niri session: hover timings, joined previews with the cards' fillet.
- [ ] Per-module choice seen in the menu on niri; the launcher opening on hover judged by the user.
- [ ] Side bars: peeks beside a side bar still float (I466).
