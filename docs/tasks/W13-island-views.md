# Card W13-island-views — the expanded family views to the Island brief

**UX brief (governs this card):** `docs/ux/island.md` — section 5 ("Family views when expanded"), Design, States, DoD.

**Read first:** `docs/tasks/README.md` (rule 10), the brief, `docs/ux/COMPOSITION.md`, `frontend/components/expanded/**`
(+ the SlotHosts W11-mod-qml added), `frontend/components/Island.qml`, `frontend/surfaces/Stage.qml`, `docs/PROTOCOL.md`
§7/§8 (svc.media players/position, svc.notifications, svc.audio sources/streams, svc.brightness, runtime.island fields
from W13-island-daemon), `frontend/test-stage.sh`.

**Owned paths:** `frontend/components/expanded/**`, `frontend/components/Island.qml` (secondary activity + overflow +
peek line), `i18n/{en,ja}/island.toml` (island keys), `frontend/test-stage.sh`.

**Do:** clock view (date header + Today, keyboard month grid with optional week numbers, selected-day section hosting
`clock.expanded.day`, aside slot, footer slot); media view (art placeholder, album, player app + switcher when several,
progress interpolated from position/rate/timestamp, seek only when allowed, transport disabled with reason, output
device chip → `quick.toggle` + Audio page, lyrics slot, backdrop slot gated); notifications view (grouped by app,
actions, clear all, DND until header slot/control, redacted while locked); volume view (devices, mic, per-app streams);
brightness view (per display + reason when only one/none, night light if served). Island pill: secondary minimal glyph +
"+N" overflow, hover peek line (dismissible/hoverable), stale rendering. Every section that lacks data shows its reason
line, never a blank.

**Acceptance:** extend `frontend/test-stage.sh` against the mock: one screenshot per view and per state the mock can
produce (several players, no seek, stale, empty agenda, locked redaction if feasible), keyboard paths, no QML errors;
read every shot critically. Report each DoD item.
