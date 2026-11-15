# Inbox — bugs and ideas, by area

**For the user to write in, for whoever works on an area to read first.** One line per thing, under the area it belongs
to (or under *Unsorted* — the lead files it). No ids, no table, no format beyond the tag:

```
- [bug] the timer's ring flickers when a second timer ends
- [idea] a "repeat last" row in the timer's menu
- [ask] should the weather card show the wind?
```

**The rule (CLAUDE.md "Workflow"):** before work on an area starts — a card is written, an agent is briefed, the lead
picks up a step — its section here is read. What fits the work at hand (the same files, small) is done with it and
ticked with where it landed; what does not fit stays, and the report says why. A line that needs design or its own card
gets a `docs/BACKLOG.md` row and keeps a pointer here (`→ I583`), so this file stays the view by area and BACKLOG the
record. Done lines are removed at the next session's start (git keeps them; the CHANGELOG says what shipped).

```
- [x] [bug] the timer's ring flickers…  — fixed S35.2 (a1b2c3d)
- [idea] a visual designer for mods → I564
```

## Unsorted

## Shell
### Bar and its modules
### Island
### Stage, panels and cards
### Launcher
- [idea] a `>` command that needs words shows nothing until they are typed: a hint row that keeps the launcher open → I572
- [bug] `test-launcher` expects a Settings page `bar`; the schema's is `layout` → B145 (W96)
### Quick settings
### Sidebars
### Dock
### Desktop and desk cards
### Notifications and toasts
### OSD
### Lock and greeter
### Menus (right-click)
### Settings app
- [ask] should a mod's row in the sidebar show its icon beside its state mark? → I573
### Theming: looks, styles, palettes, texture, motion, fonts
### Windows, workspaces, outputs

## Daemon
### Config, profiles, provenance
### Protocol and documents
### Services (audio, network, power, media, idle, night light, …)
### Performance and memory
- [bug] the running shell holds 1.9 GiB after 42 h: the daemon 641 MiB, the frontend 597 MiB → B147 (W90)

## Mods
### The mod system (contract, check, scaffolder, editor, catalogue)
- [idea] a visual designer for mods, once portable mods have a UI vocabulary → I564
### ai
### calendar
- [bug] sekai: Escape in an event's details closes the whole card → B145 (W96)
### handwriting
### lyrics
### sessions
### sysmon
- [bug] "End" on a process sends no TERM, and a refused End is not shown as refused → B145 (W96)
### tasks
- [idea] `> note <text>` appends to the notes (today only `> task <text>`; `tasks.notes.set` replaces the whole note)
### terminal
- [bug] the card sometimes comes to rest before its text is there → B145 (W96)
### timer
- [bug] clicks on the glance and the panel's rows do nothing in the suite (start, pause, resume, +1 min, stop): the product or the suite? → B145 (W96)
### wallpaper
### weather
### webdock
- [bug] a click on the bar widget does not ask for the dock's card → B145 (W96)
- [bug] 20 reveal/hide cycles grow the shell by 5–6.6 MiB (budget 1) → B145 (W96), W90

## Around the shell
### Nix, packaging, Home-Manager
- [idea] a version bump should not rebuild every dependency → I577 (W97)
### Tests, suites, workflow
### Docs
