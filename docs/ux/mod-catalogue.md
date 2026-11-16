# Mod catalogue — UX brief (session 35, K155, I570, W98)

The user (session 34): "how we could organize the mod/plugin catalogue properly". Decided then (K155): the catalogue is an
**index repository** with Nix beside it; a mod with code of its own ships as a host program (W93); first-party mods stay
in the tree for now. This brief settles what a person sees and does: finding a mod, reading what it will do before it is
installed, installing, updating, removing — in Settings, from the command line, and declaratively.

One source of truth again (rule 3): what an entry says a mod provides, uses and runs is not written by its author into the
index — it is `kurashi mod check --summary` run on the mod's source by the index's CI, the same check the daemon runs at
install. The page shows the daemon's answer, never its own reading of a manifest.

## How others do it
- **VS Code Marketplace / Open VSX** — a central registry; an entry's page carries the README and "Feature Contributions"
  (what the extension adds, read from its manifest); installs and updates in the editor, updates automatic by default.
  Open VSX is the vendor-neutral registry with namespace ownership (https://open-vsx.org). Extensions run unsandboxed;
  trust is the publisher's badge.
- **Raycast Store** — every extension is a pull request to one repository (https://github.com/raycast/extensions); the
  review is the gate; the store page lists the commands an extension adds; updates arrive by themselves.
- **HACS** (Home Assistant) — an index of repositories kept by pull request, plus "custom repositories" by URL; installs
  a tagged release into the config folder, says when a restart is needed, shows updates as entities; warns that nothing
  is reviewed for safety (https://hacs.xyz).
- **GNOME Shell** — extensions.gnome.org reviews uploads; `shell-version` in the metadata decides whether an entry is
  offered to this shell; Extension Manager browses in an app; an extension that does not fit is shown as out of date.
- **KDE Get Hot New Stuff** — the store's content behind a dialog per kind of thing; little review. In March 2024 a
  global theme from it ran a script that deleted a user's files; KDE answered with a warning before installing anything
  that can run code. The lesson is the one K155 already drew: say in plain words when a thing runs a program.
- **nixpkgs plugin sets** (`vimPlugins`, `vscode-extensions`) — pinned revision and hash, reviewed by pull request,
  declarative; nothing in the app.
- **Zed** — an index repository (https://github.com/zed-industries/extensions): one TOML naming each extension's git
  repository and revision; CI builds; the editor browses and installs; extension code runs in WebAssembly.
- **Noctalia, DankMaterialShell** — a registry repository of plugins with a list inside the shell's settings; install is
  a git clone; no hash, no statement of what a plugin reaches.

What to take: Zed's and HACS's index by pull request, with a pinned revision **and a hash**; GNOME's version range and
its honest "does not fit"; VS Code's page of contributions — ours is richer, because K154 makes a mod declare what it
provides, what it uses and what it may run; KDE's lesson; Nix's pinning as a first-class route, not an afterthought.
What none has and we do: an **update shows what changed in what the mod reaches** before it is taken.

## Design
**The index.** A git repository, one file per mod, `mods/<id>.toml`:
```toml
id = "tea"
name = { en = "Tea timer", ja = "お茶タイマー" }
description = { en = "Steeping times in the bar.", ja = "…" }
icon = "emoji_food_beverage"
author = "…"; homepage = "…"; license = "MIT"
[[version]]
version = "1.2.0"
shell = ">=0.4, <0.6"                      # the shell versions it was checked against
source = { git = "https://…/kurashi-tea", rev = "4f2a…" }   # or { archive = "https://…/tea-1.2.0.tar.gz" }
hash = "sha256-…"                          # SRI hash of the unpacked tree (the one Nix computes: one hash for both routes)
[version.summary]                          # written by CI: `kurashi mod check --summary`
provides = ["bar:tea", "panel:tea", "action:tea.start"]
uses = ["doc:svc.clock", "action:notify.send"]
capabilities = ["net:https://api.example.org"]
hosts = [{ name = "main", exec = "tea-host", start = "subscribed" }]
```
CI on a pull request fetches the source, checks the hash, runs `kurashi mod check` (errors fail it) and writes the
summary; on merge it builds one `index.json` from all files. A pull request is the review.

**Fetching.** Only when asked: Browse is opened, `kurashi mod list --available`, or "Check for updates". One GET of
`index.json` (its ETag kept), cached under `$XDG_CACHE_HOME/kurashi/mods-index/`; never polled, no job (Ma). The index's
URL is a setting (`mods.index`, default the project's), so a group can keep its own.

**Installing.** `mod.add {id, version?}`: the daemon downloads the source, verifies the hash (a mismatch writes nothing),
runs the check (an error refuses, with the check's lines), unpacks to `$XDG_DATA_HOME/kurashi/mods/<id>/` and writes
`.source` there (index, version, revision, hash, when). The mod arrives **switched off**: installing and enabling are
two acts, and the switch is where a host program's sentence stands (W93: "This mod runs a program: tea-host").
`kurashi mod add <id>[@version]`, `update [<id>]`, `remove <id>`, `list --available`; `add --from <folder|git url>` for a
mod outside the index, said as such ("not from the index: nobody reviewed it").

**Settings › Mods.** Two views in one page (a segmented control): *Installed* (today's list) and *Browse*.
- Browse: a search field (name, description, what it provides: "bar", "desk"), then rows — icon, name, one line, version,
  and one state chip: *Installed*, *Update*, *Not for this version*, *Managed by Nix*. Only the rows in sight exist
  (a list view; W90's lesson).
- An entry's page: the description; **What it adds** (its points, in words: "a bar module", "a desk card"); **What it
  reads and calls** (its `uses`); **What it may reach** (capabilities); **Runs a program** when it has a host; version,
  the shell range, the source as a link, the hash's first 12 characters; then *Install* / *Update* / *Remove*.
- An update's sheet lists what changed in those four groups ("now also reads `svc.media`", "now runs a program") and
  asks once. Nothing changed: the button updates without a sheet. Updates are never taken without the user.

**Nix.** `programs.kurashi.mods.<id> = { rev = "…"; hash = "sha256-…"; }` (the source read from the index pinned in the
flake's lock, or `src = …` given outright) puts the same tree into the store and among the daemon's mod roots, read-only.
The page shows such a mod with provenance `nix`; *Update* and *Remove* are inert with the reason ("Managed by
Home-Manager: change it in your configuration"), as every forced setting is (rule 2).

## States
| State | What is shown |
|---|---|
| The index loads | the list's skeleton rows for at most a second, then the rows |
| Offline, an index in the cache | the cached rows, "As of <time>. Offline." above them; *Install* inert ("Offline") |
| Offline, no cache / the index fails | an empty state with the reason and *Try again*; Installed stays usable |
| An entry does not fit this shell | the row dimmed, *Not for this version (needs 0.6 or later)*; *Install* inert with that |
| The hash does not match | the install stops, nothing is written: "The download is not what the index describes." with both hashes' starts |
| The check finds errors | the install stops: the check's lines, and where to report |
| Installing / updating | the button turns into progress (downloading, checking, unpacking); *Cancel* until unpacking |
| Installed, off | the row in Installed with its switch off; a toast-free note on the entry: "Installed. Turn it on in Installed." with a link |
| An update exists | *Update* chip; the sheet with the change in reach when there is one |
| Managed by Nix | provenance chip, inert buttons with the reason |
| Removed | its files go; its settings in the user's config stay and the note says so (*Also remove its settings*) |
| A mod with a host program | the "Runs a program" paragraph on the entry and at the switch (W93) |

## Keyboard, a11y, motion, outputs, Ma
The search field has the focus when Browse opens; arrows move through the rows, Enter opens an entry, Escape goes back;
every chip's state is in the row's accessible name ("Tea timer, version 1.2, update available"). Progress is a
determinate bar where the size is known, else the look's indeterminate one; reduced motion: no slide between list and
entry. Nothing here draws on an output; nothing runs while the page is closed.

## Fit
Mods page: Installed keeps its rows, switches and reasons (K25); "New mod…" (W94) stays there. Launcher: `> mods` opens
the page, `> add mod <words>` opens Browse with the search filled. The Mod Editor's last step offers "Publish": the lines
for the index file, to paste into a pull request.

## Budget
Closed: nothing (no job, no timer, no connection). Browse open: one request, the index parsed in the daemon (an index of
500 entries is about 300 KB), the page's rows virtualised. An install is the daemon's blocking work, off the runtime.

## Definition of done
1. An index repository's layout and its CI script (`tools/mod-index/build.py`) with the scaffolded example mod as its
   first entry; `kurashi mod check --summary`.
2. `mod.index`, `mod.add`, `mod.update`, `mod.remove` in the daemon with fixtures and PROTOCOL rows; the CLI over them.
3. Browse and the entry page with every state of the table drawn (mock), seen on niri in light and dark.
4. A refused hash and a refused check write nothing (tests); `.source` is written and read back.
5. The update sheet shows a change in reach; no change, no sheet.
6. `programs.kurashi.mods` with one pinned mod evaluates and the page shows it as managed.
7. Keyboard only: find, read, install, turn on, remove. i18n en and ja. Closed page: 0 frames, no request.
