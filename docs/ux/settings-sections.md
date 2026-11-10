# Settings: sections in the sidebar, and a place for every option — brief for I464 (session 27)
Status: step 1 built (the sidebar's sections). Steps 2 to 4 are design.

## Job
User, 2026-11-10: Appearance is very long. The sidebar keeps the page; a click on it shows all of it; under it its
sub-sections can be reached one by one; the sidebar marks where one is. A click on a sub-section shows that one alone.
Options should have a path a plugin can name (`Appearance:Colours`, `Motion:Profiles`) so a plugin's options sit among
the native ones, and native modules are wired the same way. Bar modules and widgets get a parent section of their own
with an icon each; the plugin dot moves to the right, smaller.

## How others do it (not checked for this brief; from memory)
GNOME Settings: flat pages, some with sub-pages. KDE System Settings: a two-level tree, the second level in the
sidebar under its parent; modules from plugins (KCMs) name their parent category in their metadata — the model for
the option path. macOS System Settings: flat list, sub-pages as drill-ins. Windows 11: a tree by drill-in with a
breadcrumb. VS Code: a tree whose node in view is marked as the page scrolls — the model for the mark.

## Step 1 — built (`feat/s27-settings-sections`)
- The open page lists its sections under it in the sidebar: the schema's sections (`#[kurashi(page, section)]`) and
  the appearance packs' blocks (Style, Look, Palette), in the page's order, by their card titles. A page of one
  section lists nothing.
- The section in view is marked (a bar and a bolder name: not colour alone), following the scroll.
- A click (or Enter/Space: each is a tab stop) on a section shows **that section alone**; a click on the page shows
  **all of it** again. Search ignores it (a search shows hits from everywhere).
- Mods' pages are unchanged (a mod's page lists no sections yet).
- Test hooks: `settings` IPC `showSection`, `sectionInView`, `soloSection`. Seen on nested niri; no suite step yet.

## Step 2 — option paths (design)
A setting's place is already `page` + `section` in the schema, and a mod's settings (`mod.toml` `[[setting]]`) all go
to the mod's own page. Add an optional `place = "<page>:<section>"` to a mod's setting and section: the row is then
listed on that core page, in that section or in a new section the mod names (with the mod's name as a small tag on
the row, Shōjiki: one sees where an option comes from), and stays reachable on the mod's page. The daemon validates
the path (an unknown page is a problem listed on the Mods page). Native modules use the same attribute, so a module
that becomes a mod keeps its place. Contract: MODS.md "Settings integration", `settings_meta` (a row gets `from`).

## Step 3 — a parent for modules (design)
The sidebar gets groups: **Shell** (Layout … Keys), **Modules** (every bar module and widget, core and mod: Clock,
Workspaces, System monitor, Tasks, Timer, Wallpaper, Web dock …), then Changed, Mods, Profiles. Each module has its
icon (a mod's from `mod.toml` `icon`, else a generic one); the state dot sits at the right, 6 px, with "(plugin)" in
its accessible name.

## Step 4 — scrolling out of a section (design)
Instead of showing one section alone: keep the whole page, snap the scroll at a section's ends and ask for a second
push (rubber-band) to leave it. The user named both; alone is built because it needs no tuning by eye.

## Decisions for the user
1. Alone (built) or the resistance of step 4, or a setting for it?
2. The path's syntax (`Appearance:Colours` or the schema's ids, `appearance.colors`), and may a plugin create a
   top-level page, or only sections?
3. The group names, and whether Island, Launcher, Dock and Sidebar count as Shell or Modules.
4. Should a section's own state (collapsed/expanded list in the sidebar) be remembered per page?

## Definition of done
Step 1: [x] list, mark, alone, keyboard, a11y names; [ ] a `settings/test.sh` part; [ ] mods' pages; [ ] ja check of
long section names in the sidebar (they elide).

## Step 2, built (session 27, I479): the user's decisions
- **The sidebar scrolls** (wheel, touchpad; the keyboard brings the focused entry into view; a thin bar while there is
  more than fits). User: "it's not possible to scroll it and that makes it impossible to reach some options".
- **Sections are listed by the page's arrow**, not by opening the page: a click on the arrow, or Right on the entry,
  lists them; a click again, or Left, folds them away (and shows the whole page). They also stay listed while one of
  them is shown alone. Nothing is remembered: every page starts closed.
- **Scroll resistance**: with one section shown alone, scrolling on past its end (or back past its start) shows a pill
  at that end ("Keep scrolling for the whole page") that fills with the push; about three notches (420 px on a touchpad)
  open the whole page at that section, on the side the scrolling came from. The push relaxes after 1.8 s, so a stray
  notch does nothing.
- Suite: `settings/test.sh` S1 to S3.
- Open: the Modules group (Island, Launcher, Dock, Sidebar as Modules), plugin-defined top-level pages and sections
  (the path's syntax is the lead's choice), icons from a mod's manifest.

