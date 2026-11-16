# Making a mod

For anyone who wants to add something to Kurashi: a module in the bar, a card on the desk, a panel, a command.
This is the guide; `docs/MODS.md` is the reference (every manifest key, every document shape).

A mod is a **guest**. It says what it adds, what it needs and what it lets others add to it, and the shell holds it to
that. In return it gets everything the shell's own parts get: the look it is drawn in, a Settings page, the launcher,
menus, key binds, both languages. A mod that follows this guide feels like it was always there.

## 1. Choose a route

| You want to… | Route | Works today | What you write |
|---|---|---|---|
| Show something the shell already knows (the clock, the playing song, the battery, another mod's data), or open and arrange things | **Views only** | yes | a manifest and QML |
| Keep state, talk to a service or the network, run on a schedule, raise an Island face, offer launcher results | **In the shell's tree** (a Rust crate linked into the daemon) | yes — by a pull request to this repository | a crate, a manifest and QML |
| The same, shipped by yourself, in any language | **A program of its own** (a host program the manifest declares; the shell starts it and scopes what it reaches) | yes (0.4.0, section 7a) | a manifest, QML, and a program in any language that can write JSON lines to a Unix socket |
| Logic without a build, sandboxed | **Luau** (portable mods) | not yet (planned, `docs/MODS.md` "Tiers") | — |

How to choose:
- **Start with views only.** Most ideas that sound like they need code need a document the shell already has. Ask
  `kurashi sub <doc>` what is there: `svc.clock`, `svc.media`, `svc.audio`, `svc.network`, `svc.power`,
  `svc.workspaces`, `svc.notifications`, and every enabled mod's `mod.<id>`.
- **Go into the tree when the mod owns something**: data of its own, a poll, a secret, a process. That code runs in
  the daemon, so it is reviewed like the daemon's own, and it ships with the shell: nothing is compiled on a user's
  machine, and nothing is loaded at run time (Rust has no stable way to do that safely).
- **Do not work around the missing routes** with a view that starts a process or polls: `kurashi mod check` refuses the
  first and rule 5 (nothing runs while nothing is shown) the second. Say what you need in an issue instead.

## 2. Start from the template

```sh
kurashi mod new tea --name "Tea" --icon emoji_food_beverage --with widget,peek,panel,menu,settings
```
writes `~/.local/share/kurashi/mods/tea/` (`--dir mods` in a checkout): the manifest, one QML file per part you ticked,
`i18n/en.toml` and `i18n/ja.toml`, and a README with the checklist. It passes the check as written — keep it passing:
```sh
kurashi mod check ~/.local/share/kurashi/mods/tea
```
Restart the daemon (it looks for mods when it starts), turn the mod on in **Settings › Mods**, and place its module in
**Settings › Layout**. QML reloads when you save.

`--with` takes: `widget` (the module in a bar), `peek` (the card under it on hover), `panel` (its expanded view: a Stage
card and a sidebar section), `desk` (a card on the desktop), `tile` (a quick settings tile), `menu` (rows in its
right-click menu), `settings` (a setting on its page). `kurashi mod points` lists every place a mod can stand in.

## 3. The manifest: three relations

```toml
id = "tea"
name = "Tea"
description = "mod-tea.description"        # an i18n key
icon = "emoji_food_beverage"               # Material Symbols; shown on its Settings page and in its rows
provides = ["i18n", "widget:tea", "panel:tea"]              # what it adds
uses = ["doc:svc.clock", "action:island.expand?"]           # what it needs beyond its own (`?` = works without)
points = ["blends"]                                         # what others may add to it: `slot:tea:blends`
```
- **provides** — one entry per place. An entry the shell does not know is refused.
- **uses** — every document a view reads, every action it calls and every setting of the shell it writes
  (`intent:theme.colors.scheme`). Its own (`mod.tea`, `tea.*`, `mods.tea.*`) and a small base set (the theme, the
  strings, the config, opening its own panel or Settings) need no entry. `kurashi mod reach <folder>` prints the lines
  for what your views use today. This list is what a user reads before turning a mod on: keep it true and short.
- **points** — a place inside your mod that another mod can fill. Open one only when you will draw what arrives.

Integrating with another mod is the same as with the shell: name its document or its declared action in `uses`, with
`?` if you work without it, and draw the state where it is off. Never read a mod you did not name.

## 4. Make every feature reachable

A feature is an **action** (in-tree mods register them; views-only mods use the shell's and other mods'). Declare each:
```toml
[[action]]
id = "tea.start"
label = "mod-tea.action.start"
icon = "timer"
command = "tea"                 # `> tea 3` in the launcher
  [[action.arg]]
  name = "minutes"
  type = "int"                  # bool · int · float · string · enum · output
  range = [1, 30]
  default = 3
  rest = true                   # the words after the command

[[menu]]
at = "module"                   # your own right-click menu; "desktop" for the desktop's
action = "tea.start"
```
A declared action is listed by `kurashi act --list`, runs from the launcher's `>` mode and from a menu row, and is what
a key bind names (binds declared by a mod: BACKLOG I571); its arguments are checked before your code sees them. If something can only be done with the pointer in
your panel, it is not finished.

## 5. Answer for every place

A mod with a bar module is asked about each variant the shell has a place for: glance, peek, expanded view, desk card,
Island face, quick tile, a `>` command, a menu. Ship it, or say why not:
```toml
[skips]
island-face = "tea has no live activity once it is poured"
```
The reason is for the next person reading your manifest. "Not yet" is an honest reason; an empty one is refused.

## 6. Feel native (what `kurashi mod check` holds you to)

1. **The kit, not your own widgets.** `import qs.core` and `import qs.kit`: Label, Button, IconButton, Chip, Icon, Block,
   FocusRing, ScrollEdge, LoadingText, PeekLines, QuickTile. They are drawn by every look — washi, pixel, glass — so
   your mod is too. If the kit lacks something, ask for it; do not rebuild it.
2. **Tokens, not numbers.** Colours, sizes, radii, spacing and motion come from `Theme`. No `"#c9404b"`, no
   `font.pixelSize: 12`, no duration of your own. Never branch on a look's or a profile's name.
3. **Copy in both languages.** Every string through `I18n.tr("mod-<id>.…")`, in `i18n/en.toml` and `i18n/ja.toml`.
4. **Every state.** Draw empty, loading, an error with its reason, offline and unavailable — not only the full state.
   Show a value only when it is in effect; a control that cannot work is drawn inert and says why.
5. **Keyboard and screen readers.** Every control takes focus, shows the FocusRing, acts on Return, Enter and Space, and
   has an `Accessible.name`.
6. **Quiet.** No `Process`, no polling. A timer or an animation runs only while its view is visible; a document is
   watched only while it is shown (`Watch { doc: …; active: visible }`).
7. **Settings in the manifest.** `[[setting]]` with a `label` and a `help` key: the page, the provenance marks, undo and
   Nix support come with it. Do not build a settings view.
8. **Every output.** A bar may be on a side edge (`property bool vertical`), there may be several screens, a panel may
   be a Stage card or a sidebar section (`fillHeight`).

## 7. In the shell's tree

Read `docs/MODS.md` "Native mods" and one small mod end to end (`crates/kurashi-mod-timer`, `mods/timer`). In short: a
crate `crates/kurashi-mod-<id>` that depends on `kurashi-mod-api` only and implements `NativeMod::enable`, registering
exactly what the manifest provides — a document behind a service that runs while it has a subscriber, actions, an
Island face, background jobs with a reason the user can read, a launcher provider. Declare capabilities for what the
code touches (`network`, `exec:<binary>`, `fs:scoped`, …). Tests sit beside the crate; the suite for its views in
`mods/<id>/test/`. Before any of it: a UX brief `docs/ux/<id>.md` (how others do it, every state, keyboard, motion,
outputs, budget, definition of done). A pull request passes `just gate`.

## 7a. A program of its own (any language)

When the mod owns something — state, a poll, a device, a network call — and is not going into the shell's tree, its
code is a **host program**: a file in the mod's `bin/` that the manifest names. The shell starts it, restarts it once if
it dies, stops it with the mod, and lets it reach exactly what the manifest says (`docs/MODS.md` "Host programs").
`kurashi mod new --host python` writes a working one. The manifest:
```toml
provides = ["i18n", "service:tea", "action:tea.start", "widget:tea"]
uses = ["doc:svc.clock"]

[[host]]
name = "main"
exec = "tea-host"          # mods/tea/bin/tea-host, executable
start = "subscribed"       # runs while a view of the mod is up (the default); "enabled" or "action" otherwise

[[action]]
id = "tea.start"
label = "mod-tea.action.start"
args = [{ name = "minutes", type = "int", default = 3 }]
```
The program gets three environment variables — `KURASHI_SOCKET`, `KURASHI_SCOPE_MOD`, `KURASHI_SCOPE_TOKEN` — and
speaks newline-delimited JSON on that socket. The whole exchange:
```python
#!/usr/bin/env python3
import json, os, socket

s = socket.socket(socket.AF_UNIX); s.connect(os.environ["KURASHI_SOCKET"]); f = s.makefile("rw")
def send(m): f.write(json.dumps(m) + "\n"); f.flush()

send({"t": "hello", "v": 1, "client": "tea-host", "caps": [],
      "scope": {"mod": os.environ["KURASHI_SCOPE_MOD"], "token": os.environ["KURASHI_SCOPE_TOKEN"]}})
send({"t": "pub", "doc": "mod.tea", "data": {"available": True, "steeping": False}})   # the mod's document
send({"t": "serve", "id": "1", "actions": ["tea.start"]})                               # the mod's actions

for line in f:                                   # the shell calls; the program answers with the call's id
    m = json.loads(line)
    if m["t"] == "call" and m["action"] == "tea.start":
        send({"t": "pub", "doc": "mod.tea", "data": {"available": True, "steeping": True, "minutes": m["args"]["minutes"]}})
        send({"t": "done", "id": m["id"]})
    elif m["t"] == "ping":
        send({"t": "pong"})
```
What to know:
- **The views read `mod.tea` as any document**, and `kurashi act tea.start`, `> tea` and a key bind all reach the
  program. Arguments arrive checked against the `[[action]]` declaration, defaults filled in.
- **Nothing undeclared is taken.** A `pub` of a document the manifest does not provide, or a `serve` of an action it
  does not declare, is refused and logged. To read or call beyond the mod's own, name it in `uses` and `sub` / `act`.
- **Idle is silent.** With `start = "subscribed"` the program does not run while no view is up; write it so that it
  can stop at any time (keep state in `{state_dir}`, passed as an argument). A program that must watch with no view up
  says `start = "enabled"`, and the Mods page shows it as running.
- **While the program is away** the document reads `{"available": false, "reason": "mods.host.starting"}`: draw that
  state in the views (a `LoadingText`), not an empty card.
- **It is your code, running as the user.** The Mods page says so before the first enable, with the program's name.
  Do not ask for more than you need: every capability and `uses` entry is shown to the person who installs it.

## 8. Before you share it

- `kurashi mod check <folder>` passes, and its notes are gone or explained.
- You used it with the keyboard only, in a light and a dark look, in a pixel look, on a side bar, in Japanese.
- With it on and nothing shown, the shell is as idle as without it.
- The manifest's `uses` and `capabilities` are what you would want to read before enabling someone else's mod.

There is no catalogue yet (BACKLOG I570): share the folder, or a repository of it. A mod in
`~/.local/share/kurashi/mods/<id>` with the same id as a bundled one replaces it.
