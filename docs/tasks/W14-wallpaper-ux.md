# Card W14-wallpaper-ux — wallpaper to its brief, incl. theme from wallpaper (BACKLOG I27, I31, I32, I33)

**UX brief (governs):** `docs/ux/wallpaper.md` ("Beyond the basic job" 1–2: wallpaper + theme as one gesture, looks).
**Owned paths:** `crates/kurashi-mod-wallpaper/**`, `mods/wallpaper/**`, `i18n/{en,ja}/mod-wallpaper.toml`,
`crates/kurashi-theme/**` (I31 theme source `wallpaper`: palette from an image path, the pipeline stage of DESIGN-SYSTEM §2,
cached by path+mtime; and I27 `color.status.warn` role, AA on surface), `palettes/` only if needed, `docs/DESIGN-SYSTEM.md` §2
(document the source — allowed).
**Do:** theme source `wallpaper` (config `theme.source = "wallpaper"` or the existing palette key's choices — read the schema
first; a schema change is a CONTRACT-CHANGE row the lead decides quickly), the picker's preview shows the theme diff (dry-run
apply) and "Apply / Wallpaper only"; favourites store {image, scheme, variant}; I32 items (keyboard grid exercised with
`tools/bench/wl_keys.py`, search/sort, grow origin from the tile, folder breadcrumb, light/dark pair badges, thumbnail cache cap,
de-duplicated first-page request); I33 the picker fills the Stage card, no nested card frame. Mods import `qs.core`.
**Acceptance:** theme tests (palette from fixture images, monochrome fallback); picker screenshots through the real shell incl.
preview-with-theme; keyboard run; every DoD item of the brief met / not met.
