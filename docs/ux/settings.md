# Settings app, mods and pickers — UX brief
Status: agreed (lead, session 5) — functional base merged (W9-config-profiles, W10-settings); UX pass: card W13-settings-ux

## Job
Change anything the shell does, understand *why* a value is what it is, and undo freely. Kurashi's edge over every
other shell is provenance (K21): each row knows its source, what overrides it, and why a control is inert. The UI
must make that visible without becoming noisy, and treat mods as first-class citizens (K25).

## References (research 2026-10-09, cited)
- **VS Code settings**: modified-bar on changed rows, `@modified` filter, per-setting gear (Reset, Copy setting link),
  `@haspolicy` and a policy diagnostics view (current vs enforced), profiles with preview and review-on-import,
  theme picker previews on Up/Down and commits on Enter.
- **KDE System Settings**: opt-in "Highlight changed settings"; kiosk-locked controls hidden or pinned (pitfall:
  inconsistent); Get New Stuff; defaults without preview (bug 145741).
- **GNOME**: panel-level search only (per-setting search requested, gitlab #2150); dconf-locked extension dimmed but
  still toggleable via CLI (issue 6045 — "dimmed is not enforced"); HIG: drop-downs for long lists, never < 3 items.
- **Firefox policies**: locked prefs; "managed by your organization" banner (also for NixOS-declared prefs) — generic
  banners hide the source (pitfall); add-on updates that add permissions are held for approval.
- **COSMIC design**: one scrollable search list across panels, "Related settings" cross-links.
- **DMS / Noctalia**: plugin scan + toggle + restart; plugins run with full session permissions.
- **WAI-ARIA APG**: switch pattern, select-only combobox, grid; WCAG 2.5.7 (no drag-only), 1.4.1 (no colour only).

## Beyond the basic job — what Settings can become
1. **Provenance you can read**: each row's chip names the layer ("Kanso profile", "you", "Nix: programs.kurashi.
   settings.theme.palette", "accessibility"); hovering shows the full `cfg.why` stack; inert rows say why in one
   line with a link to the controlling key ("Controlled by High contrast → open").
2. **"Changed" view**: a sidebar filter "Changed from default" listing every user/profile-set key across pages,
   with per-key and per-page reset that *previews the diff* first (dry-run apply exists).
3. **Live preview for visual keys**: palette, scheme, fonts, radius, bar edge preview on focus (Up/Down) and
   commit on Enter as one undo step; Esc reverts (VS Code pattern, plus Esc).
4. **Search that lands on the row**: results show breadcrumb "Appearance › Colours › Palette", Enter scrolls and
   flashes the row; deep links `kurashi settings <key>` (CLI) open it; "Copy setting link".
5. **Mods as citizens**: a mod page shows on/off first, then "Running now: …", capabilities and cost, its settings,
   its contributions (slots, faces, widgets — "Adds: weather in the clock view, a bar widget") with jump links to
   where they appear; "Changed on disk: Reload" when a manifest changes; enable refused → the error in the page.
6. **Profiles as stories**: header "Kanso · 3 settings differ — Show / Save / Revert"; profile cards with origin
   (bundled, yours, imported); load = preview diff → apply; export drops machine-local keys; import reviews first;
   Nix-forced keys listed as "not applied: set by Nix".
7. **Related settings**: footer links between pages that interact (Island ↔ Notifications ↔ Quick settings).

## Design
- Window: sidebar (search on top, core + mod pages alphabetical with state marks, then "Changed", Mods, Profiles) +
  page. Rows: label/help left, control right, provenance chip + reset under the control.
- Controls: 2 options → switch; 3–5 visible → segmented; long or dynamic → dropdown (select-only combobox: type-ahead,
  greyed options with reason as a second line, Esc cancels); ordered subsets → **vertical** pick list (rows with
  move up/down buttons, Alt+Up/Down, remove, "Add…" dropdown; one provenance for the list; never horizontal).
- Mod page header: name, on/off switch (inert + "Set by Nix" when forced), status line, description, "Adds:" list.
- Focus ring visible on every control state (the ON-switch issue fixed in the shell's ToggleSwitch applies here).

## States
default · profile · user · nix-forced (read-only, no reset, names the option) · inert (requires / mods.disabled /
restart pending / choice unavailable) · invalid input (inline, keeps the typed text) · preview (uncommitted) ·
undo/redo after external change (CLI) · empty search (names its scope) · mod: available / loaded-off / on / running
/ enable failed / invalid / removed while on · ja copy lengths.

## Fit and constraints
Settings is a thin view over `schema.settings`, `config`, `mods` (rule 1); all diffs and previews come from the
daemon (dry-run apply, `cfg.why`). New contract needs: `cfg.why` in Settings already exists; "changed" listing can be
derived from the `config` doc's provenance (no new contract); deep link = an argument to the settings app.

## Definition of done
- [ ] provenance chip names the layer incl. Nix option path; hover shows the stack
- [ ] "Changed" view with per-key / per-page reset and diff preview
- [ ] live preview for palette/scheme/font/radius (focus → preview, Enter → commit, Esc → revert)
- [ ] search lands on the row; `kurashi settings <key>` opens it
- [ ] mod page: switch, running, capabilities, "Adds:" with links, enable errors
- [ ] vertical pick list with keyboard reorder; dropdown with greyed reasons
- [ ] profiles: differ count, preview, export/import review
- [ ] screenshots of all states; keyboard-only run through every page

## Later
Related-settings links · per-slot ordering UI (K28) · settings sync across machines · a11y audit with Orca.
