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
