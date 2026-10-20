# Card W20-webdock-daemon — the hover state machine and the pin edits (K40; rows 109–111)

**Decision (user, session 8):** a rest on the dock's edge reveals the strip and re-opens the last page; a click on the
shown pin's icon puts it away; a click into the dock keeps it until keyboard focus leaves; reveal 250 ms (500 ms on a
shared edge), hide 400 ms; pinned holds it; new tabs stay in the dock (setting `new_tabs`); "replace pin with this
page". The daemon owns all of it (rule 1); the shell (W20-webdock-shell) and the host (W20-webdock-host) only send
the events. Those two cards run in parallel and test against **your mock parity**.
**Brief:** `docs/ux/webdock.md` ("User decisions (session 8)", "Modes and transitions", "Definition of done": every
transition has a daemon unit test).

**Read first:** `docs/tasks/README.md` (rules), DECISIONS K40 + K38, MODS.md "Web dock" (the frozen contract; the
"Shell side" paragraph is new), `fixtures/ipc/server/snap_mod_webdock.json`, `mods/webdock/mod.toml` (the new
settings), `crates/kurashi-mod-webdock/src/{lib,dock}.rs`, `crates/kurashi-mock/src/webdock.rs`,
`crates/kurashid/tests/webdock.rs`.

**Owned paths:** `crates/kurashi-mod-webdock/**`, `crates/kurashi-mock/src/webdock.rs` (and only the routing lines
for the new `webdock.*` actions in `crates/kurashi-mock/src/state.rs`, if routing is not by prefix already),
`crates/kurashid/tests/webdock.rs`, `i18n/{en,ja}/mod-webdock.toml` (append only: error and action keys). Not yours:
`mods/webdock/mod.toml` (settings are frozen), `mods/webdock/{host,qml,test}/`, `frontend/`, `nix/`, every other
crate. Sandbox/tmp names start with `w20-dmn-`.

**Do:**
1. **Config + document** (row 109): read `hover`, `reopen_last`, `pinned`, `reserve`, `indicator`, `strip`,
   `new_tabs`; serve `pinned`, `engaged`, `hover`, `reserve`, `indicator`, `new_tabs`, `geometry.strip` (the setting,
   replacing `STRIP_PX`) and `geometry.grace` (24). The fixture is the shape.
2. **Hover state machine** (row 111, MODS.md "Shell side"): `webdock.hover {part: edge|strip|card, inside, output,
   shared?}` and `webdock.engage {on}`. Track which parts are inside on the latched `output`. Reveal: hidden + edge
   inside + `hover` on → arm 250 ms (500 ms with `shared`), the edge's output becomes `output`; edge leave disarms.
   Fire → compact, plus extended(`shown`) when `reopen_last` and `shown` is set (a web pin starts the host, as
   `toggle` does). Hide: shown, no part inside, not `pinned`, not `engaged` → arm 400 ms; any inside disarms; fire →
   hidden (`shown` kept), `engaged` false. `engage {on:false}` counts as a leave (arms the hide; a following
   `engage {on:true}` from the other part disarms it). Events from another output are ignored while shown. `toggle`
   reveals with `engaged` = true, hides with `engaged` = false. **Deadlines live in the supervisor's `select!`** next to
   the idle deadline; nothing is armed while nothing is pending (rule 5). Pure transition logic in `dock.rs`, taking
   `Instant`s, so tests need no runtime.
3. **Clicks and keys:** `webdock.select {pin, output?}` (extended(pin); compact + `shown` cleared when that pin is shown
   and extended), `webdock.back {}` (extended → compact, `shown` cleared; compact → hidden unless pinned).
4. **Settings writes** (undoable, through the existing `SettingsWriter`, refusals mapped like `view`):
   `webdock.pin {on?}` → `pinned` (no argument flips the value in effect); `webdock.add {url, title?}` → a new row
   (`id` = a slug of the URL's host without `www.`, `-2`, `-3`… when taken; `title` = the argument or the host;
   `target` = url; schemes as the setting allows) and the reply `{pin: id}`; `webdock.remove {pin}`;
   `webdock.move {pin, to}` (0-based, clamped); `webdock.retarget {pin, url}` (web pins only; http, https, file).
   Every write keeps every other field of every row (as `view_rows` does).
5. **Mock parity** (`kurashi-mock/src/webdock.rs`): the same document fields and actions. The mock applies reveal and
   hide **at once** (no timers — say so in its doc comment) and edits `pins` in its document directly for the settings
   writes. Keep `mock.webdock {…}` working.
6. i18n: action labels `action.webdock.{hover,engage,select,back,pin,add,remove,move,retarget}` and any new error keys,
   en + ja.

**Acceptance:** `timeout 900 cargo test -p kurashi-mod-webdock -p kurashi-mock` and
`timeout 900 cargo test -p kurashid --test webdock` green, covering **every row of the brief's transition table**
(tokio paused time for the 250/500/400 ms deadlines: reveal fires, early leave disarms, shared edge waits 500, rapid
enter/leave ×20 ends in a consistent state, pinned and engaged hold, engage handoff strip→card does not hide, other
output ignored, `reopen_last` on/off, `hover` off ignores the edge), `select` toggle, `back` from each mode, `toggle`
sets `engaged`, `add` id derivation and collision, `move` clamp, `retarget` refuses a view pin and `javascript:`, a
write keeps the other rows' fields, the document matches the fixture's keys. `cargo clippy -p kurashi-mod-webdock -p
kurashi-mock --all-targets -- -D warnings`; `cargo test -p kurashid` stays green.
