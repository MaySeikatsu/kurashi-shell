# Mod Editor — UX brief (session 34, K154, I563)

The user (session 34): "a mod editor that helps templating mods … templates for plugins and what they should support
(maybe with checkmark list for potential integrations) and visual designer"; "rulesets/templates should guarantee it to
feel native … proper settings integration with icon and all". Decided: the ruleset, the scaffolder, the check **and** the
editor now; the visual designer waits for the portable tier's UI vocabulary (MODS.md "Tiers").

The editor is a face of one generator: `kurashi mod new` (CLI), the action `mod.new` (daemon) and this page write the
same files from the same templates, and `kurashi mod check` / `mod.check` judge the result (rule 1, rule 3). The page
holds no knowledge of its own: the checklist is the points registry (`query points`), the actions and documents it offers
are the daemon's (`query actions`), the rules are the check's.

## How others do it
- **VS Code** — `yo code`, a terminal wizard: kind of extension, name, id, description, then a folder that runs
  (https://code.visualstudio.com/api/get-started/your-first-extension). What an extension adds is declared in
  `contributes`, and the editor shows it on the extension's page ("Feature Contributions"). No in-app creator.
- **Raycast** — "Create Extension", a form inside the app: template, title, icon, command type; writes the folder and
  opens it (https://developers.raycast.com/basics/create-your-first-extension). The store review is the ruleset.
- **GNOME Shell** — `gnome-extensions create --interactive`: name, description, uuid, a template (plain, indicator,
  quick settings) (https://gjs.guide/extensions/development/creating.html). Nothing checks the result.
- **KDE Plasma** — a widget is a package with `metadata.json`; templates through KAppTemplate, `kpackagetool6` installs,
  `plasmoidviewer` previews one outside the shell (https://develop.kde.org/docs/plasma/widget/).
- **Obsidian, Decky, Noctalia, DankMaterialShell** — a sample repository to copy; rules in a README.
- **Home Assistant** — `python -m script.scaffold integration`: questions, then files and the tests that hold them.

What to take: Raycast's in-app form (no terminal needed), GNOME's templates by *what it is*, Home Assistant's "the
scaffold also writes what checks it", KDE's preview outside the running shell. What none has and K154 asks for: the
checklist of places a module can stand in, with a reason for each one left out.

## Design
A page of Settings, opened from the Mods page ("New mod…") or `settings.open {page: "mods.new"}`; `> new mod` in the
launcher. Two columns in a wide window (form left, result right), one below the other when narrow.

**Form** (one scroll, four groups; no wizard steps — every answer stays visible, Kanso):
1. **What it is** — name; id (a slug made from the name while untouched; `[a-z0-9-]`, 1..32); icon (the shell's icon
   picker: the subset first, search); one line of description.
2. **Starts as** — one card: *Bar module* (glance + peek + panel), *Panel* (a card and sidebar section), *Desk card*,
   *Command* (a `>` action and nothing drawn), *Blank*. A card presets group 3; it is a start, every tick can change.
3. **Where it shows** — the checklist, from the points registry: glance, peek, expanded view, desk card, island face,
   quick tile, `>` command, menu rows, a settings page, and the core views' slots (clock aside, media below, …). A
   placeable module's unticked variant asks for its reason in one line (`[skips]`), with a suggestion to accept.
4. **What it uses** — documents and actions beyond its own, picked from the daemon's lists with search (`svc.media`,
   `island.expand`, another mod's declared actions), each required or optional. Then **Runs on**: *Nothing of its own*
   (it draws documents it uses), *A program of its own* (a host process in any language: the template is a small script
   that says hello on the scoped socket and publishes one document), *Rust in the shell's tree* (first-party: shown only
   in a checkout, writes `crates/kurashi-mod-<id>`), *Luau* (listed, inert: "with portable mods").

**Result** (right):
- **Files** — the tree that will be written, each file openable as a read-only preview (the manifest first).
- **Check** — the ruleset's verdict on the form as it stands, live: one line per rule, met or not, with what to change.
- **Create** — writes `$XDG_DATA_HOME/kurashi/mods/<id>/` (a checkout: `mods/<id>/`), then offers *Turn it on*, *Open the
  folder*, *Open its page*. The mod is `available` at once (the registry rescans); nothing is enabled without the click.

## States
| State | What shows |
|---|---|
| Fresh | The form with *Bar module* chosen; Create inert with "Give it a name". |
| Id taken / invalid | The id field's error line (`mods.new.error.id_taken`, `…id_invalid`); Create inert with the reason. |
| A variant unticked without a reason | That row's field outlined; the Check line "says why it has no peek" not met. |
| Daemon away | The lists of group 4 empty with "The shell is not running"; the form stays; Create inert with that reason. |
| Folder not writable | Create's error under the button with the path (`mods.new.error.write`); nothing half-written (a temp dir, then a rename). |
| Config forced by Nix | "Turn it on" inert with the provenance reason (`config.forced.nix`); the folder is still written. |
| Created | The result column becomes the three follow-ups and the check's report on the written files. |
| Check fails after an edit by hand | The mod's own Settings page shows the same report (the Mods row: "3 rules not met"). |

## Keyboard, a11y, motion, outputs, Ma
Tab walks the groups in order, arrows inside a card row and the checklist, Space ticks, Enter on Create; Esc goes back to
the Mods page (a form with input asks first). Every control has its `Accessible.name`; the check's lines are a list with
role and state ("met"/"not met"), not colour alone. Motion: the look's own for the result column's change; none of its
own. It is a Settings page: one window, any output. Nothing runs while the page is not shown; the check runs on a change
of the form (debounced by the daemon's own coalescing of the query), not on a timer.

## Fit
Mods page: a "New mod…" row at its top and, per user-made mod, "Check" and "Open the folder". Launcher: `> new mod`.
The mod it writes lands in the same places every mod does: its Settings page with its icon, the module picker, the
sidebar's "+", the desk's edit mode, the quick tiles' list.

## Budget
The page costs nothing closed (a Loader). Open: no document of its own; two queries on open (`points`, `actions`), one
`mod.check {draft}` per change. No frame at rest.

## Definition of done
- [ ] `mod.new`, `mod.check`, `query points` exist, with fixtures; the CLI and the page call the same code.
- [ ] Every template passes `kurashi mod check` as written (a test generates each and checks it).
- [ ] The page: all four groups, the live check, Create and its three follow-ups; every state above drawn and shot on niri,
      light and dark, in two looks.
- [ ] Keyboard only: a mod created, turned on and placed in the bar without the pointer.
- [ ] A mod made by the page shows its icon on its Settings page, in the Mods row, the module picker and the launcher.
- [ ] en and ja copy (`i18n/{en,ja}/mod-editor.toml`).
- [ ] The visual designer is a BACKLOG row, not a stub in the page.
