# Groups on the bar and in sidebars; adding modules in place (session 30: I502, I500 c)

The user's points 12 and 4e (named groups, decided 2026-11-12: Noctalia v5's capsule groups as the model; the bar's
automatic grouping stays as it is today by default) and 4c (a "+" to add or remove what a sidebar shows).

## How others do it
- **Noctalia v5** ([bar docs](https://docs.noctalia.dev/noctalia/v5.4.0/bar/)): a lane lists `group:<id>`; the group is
  `[[bar.<name>.capsule_group]]` with `id`, `members`, style (fill, border, padding, radius, opacity), `accordion`
  (collapsed to its first widget until hovered; direction, duration, delay) and `widget_spacing`; per-monitor overrides
  by id. Settings: drop a widget onto another (or tick several, Group); drag in, drag out or eject a member; Ungroup.
- **Waybar**: `group/<name>` modules with `orientation` and a `drawer` (an accordion that slides open on hover).
- **HyprPanel / Caelestia / end-4**: fixed "islands" per section, not user-made groups.
- **KDE Plasma**: panel spacers and widgets, no groups; **GNOME** none; **macOS** none (menu-bar extras only).
- **Sidebar sections**: Android 16 quick settings and macOS Control Centre group tiles by module, not by user; Noctalia
  has no sidebar. Our pages mode is the closest to Arc's spaces.

## Design
- **One model for both.** A list entry `group:<id>` stands for a group; `[[layout.groups]]` holds
  `{id, members, accordion = false, name = ""}` (one table for bar zones and sidebar section lists; a member is a module
  id or a section id). A member listed in a group is not listed again outside it. Schema: a records setting (K38), so
  Settings, defaults, validation and docs are generated (rule 3).
- **On the bar** a group is one framed container: the look's group block (chrome with groups: the outlined box under
  line, the keycap or soft block under keycap and soft) round its members, several per zone. `bar.grouping`:
  *Automatic* (today's runs: the island and the window list apart, every other stretch one block — the default) or
  *One per zone* (each zone's modules one block). Named groups apply in both and split what they hold from the rest.
  Accordion: collapsed to its first member until hovered or focused, opening toward the zone's middle (motion
  `motion.std`, off under reduced motion), keyboard: Tab enters and opens it.
- **In a sidebar**: one column — a group is its members stacked in one card with a heading (`name`); pages — a group is
  one tab whose page stacks its members (the user's "combines the groups into one page").
- **Making groups.** Settings (Layout › Bar, Sidebar): drag a module onto another to group them, onto a group to join it,
  out to leave it; select several + "Group"; the group's row has its name, Accordion and Ungroup. In the shell: the
  module menu (right click) has "Group with…" and "Leave group".
- **"+" in place (4c).** At the end of a sidebar's tab row (pages) or under its last section (one column) a "+" key opens
  a picker of what can be added (the sections and every mod panel, with what is already shown ticked); untick to remove.
  It writes `sidebar.<side>.sections` (one transaction, undoable). The bar's own edit mode is the module menu (today).

## States
Empty group (no member on: hidden, its id kept); a member whose mod is off (skipped, as sections are); a forced list
(the "+" and the drag show why they are inert, Shōjiki); one member (drawn as a plain module).

## Fit, budget, done
Island, window list and tray keep their own shapes. No new process; groups are layout only (0 frames at rest).
Done: Settings drag/drop and the module menu both make and dissolve groups; bar and sidebar draw them in every chrome;
keyboard and a11y names ("Group: <name>, 3 modules"); seen on nested niri on two outputs.

## Round two: editing groups (session 32, W80; I502, I508)
The user (session 32) chose both places to drag: the zone lists in Settings first, then a small bar preview.

**How others edit.** Noctalia v5's bar settings: drop a widget onto another to make a capsule group, drag a member out or
eject it, Ungroup on the group; tick several + Group. GNOME has no groups (Shell extensions reorder only). KDE Plasma's
panel edit mode drags widgets along the panel (no groups; a "panel spacer" separates). Waybar: groups are text only.
macOS: Cmd-drag reorders menu-bar extras, nothing groups. So a drop onto a module is the model; we add the keyboard path
Noctalia lacks.

**The list (Layout › Bar zones, Sidebar sections).** A group stands in the list as one row (`group:<id>`): its name
(editable in place; empty shows the id), an Accordion switch and Ungroup; its members are indented rows under it, each
with Leave group. Gestures, each one transaction (`layout.groups` and the zone list in one `apply`, one undo step):
- a module dropped **onto a module** → a new group of both (id `g<n>`, the first free; name empty), where the target was;
- a module dropped **onto a group** (its row or a member) → joins it at the end;
- a member dropped **outside its group** (another top-level row's edge, or the list's empty end) → leaves it: it stands
  right after the group; the last member out dissolves the group (the record goes, as Ungroup);
- a group dropped **onto a group** → a confirm under the target ("Merge <a> into <b>?" Merge · Cancel); Merge appends the
  dragged group's members and removes its record.
The rows show the daemon's answer only (Shōjiki): nothing regroups before the apply is in effect; a refusal stays on the
row's line. The drop target highlights (container-high fill, accent edge) while a drag is over it.

**Keyboard (no drag needed).** On a top-level row: Ctrl+Down / Ctrl+Up = drop it onto the next / previous row (group with
it, or join it when that row is a group); on a member: Ctrl+Left = Leave group; on a group row: Delete = Ungroup (its
members stay, in order, where it stood), Ctrl+Down/Up onto another group asks to merge (Return confirms, Escape cancels).
Every gesture also has a button (Leave group, Ungroup) for the pointer and for screen readers. The focus follows the
moved module.

**The module menu (right click on a bar module).** "Group with…" — a submenu of the zone's other modules and groups (a
group is named "Group: <name>"); "Leave group" while the module is in one. Both write the same ops as the list.

**The bar preview.** Under the zone lists: the selected output's bar as it draws (start · center · end), small, each
module a chip by its name, a group one framed chip of its members. The same drops work on it (a chip onto a chip, onto a
group, a member out to the zone's gap); Tab walks the chips and Ctrl+arrows act as in the list.

**A11y names.** A group row: "Group: <name>, <n> modules"; a member: "<module>, in <group>"; buttons "Leave <group>",
"Ungroup <group>", "Accordion for <group>"; the drop zones announce "Drop to group with <module>".

**States.** Forced list (Nix or a profile holds it): every row inert, no drag starts, the row's chip and reason say why
(Shōjiki). One member: the group row stays (with its one member and Ungroup); the bar draws a plain module. Empty group
(a record no zone lists, or with no members): not in the list; Layout › Groups (the records row) still shows it to edit
or remove. A member whose mod is off: the member row is dimmed with "not available now".

**Motion.** A drop: the moved row settles by `motion.std` (height and position); under reduced motion nothing flies —
the rows simply show the new order. No animation runs at rest (Ma).

**Done (round two).** The four list gestures and the menu make, join, leave, merge and dissolve groups in one undoable
step each; keyboard paths for each; a11y names; forced/one-member/empty states drawn; shots light and dark of the list,
the preview and the menu; seen on nested niri.
