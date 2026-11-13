# W80 — Groups, round two: drag and drop in Settings, a bar preview, "Group with…" (I502, I508; Opus)

**Base.** `feat/s32-combined`: if your HEAD does not contain `origin/feat/s32-combined`, `git reset --hard
origin/feat/s32-combined` first (fresh worktree).

**The user's answer (session 32).** Asked where the drag happens and what a drop on a group does, they found both
"the list in Settings (drop on a module groups them, on a group joins it, a group on a group merges after a confirm)"
and "a miniature bar preview in Settings" interesting — build both, the list first.
**Goal.** docs/ux/groups.md already designs groups (K145, `[[layout.groups]]`, records setting). Make them editable:
1. **UX first:** a section "Round two: editing groups" in `docs/ux/groups.md` — the list drag, the bar preview drag, the
   module menu, keyboard paths (no drag needed: select + "Group", "Move to group…", "Leave group"), a11y names, states
   (forced list: inert with the reason; one member; empty group), motion (reduced: no fly), how GNOME/KDE/Noctalia v5
   edit (Noctalia: drop a widget onto another).
2. **Settings, Layout › Bar and Sidebar lists:** drag a module onto another → a new group of both; onto a group → joins;
   out of a group → leaves; a group onto a group → merges after a confirm. Group rows: name (editable), Accordion,
   Ungroup. One transaction per gesture (undoable).
3. **A bar preview** in Settings (the zones as the bar draws them, small, per output or the default) where the same drags
   work.
4. **The module menu** (`frontend/components/ModuleMenu.qml`, right click on a bar module): "Group with…" (a submenu of
   the zone's other modules and groups) and "Leave group".
**Owned paths.** `settings/**` except `settings/shell.qml`, `settings/components/DockHost.qml` (the lead's);
`frontend/components/ModuleMenu.qml`; `docs/ux/groups.md`; i18n domains you touch (`i18n/{en,ja}/settings*.toml`,
`module-menu`). The config writes go through the existing settings actions (records of `layout.groups` and the zone
lists); if you need a new action, a CONTRACT-CHANGE row.
**Acceptance.** A Settings suite part (e.g. `SETTINGS_PART=groups settings/test.sh`) on nested niri: a drag in the list
makes a group (the config holds it, the bar draws it), a drop on a group joins, Ungroup dissolves, undo restores; the
module menu's "Group with…" groups two modules; shots light and dark of the list, the preview and the menu.
**Build dir** `~/.cache/kurashi-agents-target/w80`. Time box: report by 12:40 with what is done.
