# Card W13-settings-ux — Settings to its UX brief

**UX brief (governs this card):** `docs/ux/settings.md` — implement its Design and States and meet its Definition of
done. Read the brief's References section to understand *why*.

**Read first:** `docs/tasks/README.md` (rule 10), `docs/ux/settings.md`, `docs/DECISIONS.md` K21, K22, K25, `docs/PROTOCOL.md`
§5 (cfg.why, apply dry_run/preview, config doc, schema.settings, mods doc), `settings/**`, `settings/test.sh`.

**Owned paths:** `settings/**`, `i18n/{en,ja}/settings.toml`. No daemon change: every diff/preview/why comes from existing
protocol (`apply` with `dry_run` → `preview`; `cfg.explain` → `cfg.why`). If something is truly missing, a
CONTRACT-CHANGE row and a local stand-in.

**Do (from the brief):** provenance chip naming the layer (Nix option path when `source.kind == "nix"`: `programs.kurashi.
settings.<key>`), hover stack from `cfg.why`; "Changed" sidebar view with per-key/per-page reset + diff preview; live
preview for palette/scheme/font/radius (focus/arrow → dry-run preview shown, Enter commits as one undo step, Esc
reverts); search results with breadcrumbs that land on and flash the row; settings app argument `--key <key>` opens a
row (document it); mod page header (switch, running, capabilities, cost, "Adds:" from `provides` with human labels);
**vertical** pick list (move buttons, Alt+Up/Down, remove, "Add…" dropdown, list-level provenance); dropdown with
type-ahead and greyed options with reasons; focus ring visible on ON toggles (copy the outer-ring fix from
`frontend/components/ToggleSwitch.qml`); profile header "N settings differ" with Show/Save/Revert.

**Acceptance:** extend `settings/test.sh` (KURASHI_BIN_DIR with prebuilt binaries; `KURASHI_RENDER_NODE=/dev/dri/renderD129`):
a screenshot per Definition-of-done item and per state in the brief's States list that the sandbox can produce (a
`managed.toml` with `_managed.enforce = true` gives Nix-forced rows); keyboard-only path through the new features;
no QML errors. Report each DoD item met / not met.
