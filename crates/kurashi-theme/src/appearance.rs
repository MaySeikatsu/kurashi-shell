//! Appearance packs (K53): **styles**, **looks** and (in [`crate::palette`]) **palettes**, each a file.
//!
//! - A **palette** is colours only (`palettes/<name>.toml`).
//! - A **look** is the form and feel of the UI without its colours (`looks/<name>.toml`): chrome, corners, material,
//!   motion, type — the keys in [`LOOK_KEYS`] — and its art (`[slots] frame`). Sekai's toy keycaps, washi's paper and
//!   ink, win95's bevels. A look that only recolours another one is a palette instead.
//! - A **style** is a fixed preset (`styles/<name>.toml`): a look, a palette, and the other appearance keys
//!   ([`STYLE_KEYS`]: scheme, density) plus tweaks of its own look. Applying a style resets every appearance key the
//!   user set, so the style is recreated exactly; tweaks made afterwards show as differences from it.
//!
//! Bundled packs are compiled in; files in `$XDG_CONFIG_HOME/kurashi/{looks,styles}/` replace a bundled pack of the
//! same name or add one (WormShell's folder packs, shellseikatsu's preset manifests). A recipe entry outside its
//! kind's keys is dropped and reported: a look never moves anything and never colours anything (K45, K53).
//!
//! `[slots] frame = "<name>"` (looks only) is drawn over every block's edge by the frontend component
//! `frontend/components/frames/<Name>.qml` (kebab-case → PascalCase; W25). The daemon publishes it as the theme token
//! `decor.frame` (`""` when the look has none); the name is data, never compared by a renderer (rule 4).
//!
//! W53.0a (K80, docs/ux/styles.md "The shared system"): the other [`SLOTS`] work the same way — `[slots] title =
//! "caption"` is `decor.title`, which the title host loads as `frontend/components/decor/title/Caption.qml` — and a
//! look's `[decor]` table carries the numbers, switches, palette roles and curves its components share
//! ([`DECOR_KEYS`]: one list, validated here, published as `decor.<key>` with every default filled in). A slot or a key
//! outside the lists, or a value outside its kind, is refused and reported like a foreign recipe key.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

/// The look slots (`[slots]`): each a component name the frontend's host for it loads; `""` (or left out) = the
/// default, today's shell. `lock` and `sounds` are hosted by the lock surface and the daemon (W53.0b); `bar` (W53.2) is
/// the bar's ground (`decor/BarGround.qml`).
pub const SLOTS: &[&str] = &[
    "frame", "title", "start", "tray", "menu", "scroll", "tooltip", "focus", "button", "slider",
    "toggle", "lock", "sounds", "bar", "island",
];

/// What a `[decor]` value may be.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum DecorKind {
    /// A whole number within the range (px, a weight, a count).
    Int(i64, i64),
    /// A number within the range (a strength).
    Num(f64, f64),
    Bool,
    /// One of these words.
    Choice(&'static [&'static str]),
    /// A palette role's name (published as its colour); `""` = the component's own colour.
    Role,
    /// One or two role names (a solid fill or a gradient's ends).
    Roles,
    /// A QML `bezierCurve`: a cubic's four control numbers (`[x1, y1, x2, y2]`, ending at 1, 1), or whole segments of
    /// six numbers whose last point is 1, 1; `[]` = the motion profile's own.
    Curve,
    /// Font families, the first installed one wins; `[]` = the shell's own.
    Families,
    /// A shipped set's name (a slug: `cursors/<name>/` in the package); `""` = none (W53.0b, contract row 593).
    Name,
}

/// One `[decor]` key: its name, kind, default (JSON) and what it is for.
pub struct DecorKey {
    pub key: &'static str,
    pub kind: DecorKind,
    pub default: &'static str,
}

const fn k(key: &'static str, kind: DecorKind, default: &'static str) -> DecorKey {
    DecorKey { key, kind, default }
}

use DecorKind::{Bool, Choice, Curve, Families, Int, Name, Num, Role, Roles};

/// Every `[decor]` key a look may set (W53.0a, docs/ux/styles.md "Metrics, as data"), with the default that keeps
/// today's shell. Numbers are logical px unless named otherwise; `0` (or `-1` where 0 is a size) means the component's
/// own value. The tokens are `decor.<key>`; roles are published as colours. DESIGN-SYSTEM §4 "Decor metrics" says
/// what each draws.
pub const DECOR_KEYS: &[DecorKey] = &[
    // Window captions (the `title` slot): height, fill (active, inactive; one role solid, two a gradient), its
    // direction, the text's place and weight, the close button's chrome, which side the buttons sit on, the corner.
    k("title.height", Int(12, 64), "24"),
    k("title.fill", Roles, r#"["title", "title_end"]"#),
    k(
        "title.fill_inactive",
        Roles,
        r#"["title_inactive", "title_inactive_end"]"#,
    ),
    k("title.on", Role, r#""on_title""#),
    // The text of an inactive caption ("" = `title.on`): 98's silver on grey.
    k("title.on_inactive", Role, r#""""#),
    k(
        "title.fill_dir",
        Choice(&["horizontal", "vertical"]),
        r#""horizontal""#,
    ),
    k("title.align", Choice(&["start", "center"]), r#""start""#),
    k("title.weight", Int(100, 900), "700"),
    k(
        "title.close",
        Choice(&["glyph", "bevel", "gel", "plate", "dot"]),
        r#""glyph""#,
    ),
    k("title.buttons", Choice(&["end", "start"]), r#""end""#),
    k("title.radius", Int(-1, 24), "-1"),
    // The caption buttons' size, the gap before the close button and the inset from the caption's edges (W53.1: 98's
    // 16 × 14 buttons, 2 px apart from close, 2 px in); 0 / -1 = the part's own (a square from the caption's height).
    k("title.button_w", Int(0, 64), "0"),
    k("title.button_h", Int(0, 64), "0"),
    k("title.button_gap", Int(-1, 16), "-1"),
    k("title.inset", Int(-1, 16), "-1"),
    // W53.2 (XP, 7): the close button's own width (7's 43 px gel beside 25 px keys; 0 = `title.button_w`) and fill role
    // ("" = the part's own), the buttons' corner (-1 = the part's own), the title's face and size (the chain's first
    // installed family is published as `font.title`; [] / 0 = the theme's), how the title stands off its band (XP's
    // 1 px shadow, 7's soft glow behind dark text) and a gloss over the band (XP's light top and darker foot; 0 = flat).
    k("title.close_w", Int(0, 96), "0"),
    k("title.close_fill", Role, r#""""#),
    k("title.button_radius", Int(-1, 16), "-1"),
    k("title.family", Families, "[]"),
    k("title.size", Int(0, 32), "0"),
    k(
        "title.text_effect",
        Choice(&["none", "shadow", "glow"]),
        r#""none""#,
    ),
    k("title.gloss", Num(0.0, 1.0), "0.0"),
    // A window border round a captioned card: width and role.
    k("border.width", Int(0, 8), "0"),
    k("border.color", Role, r#""outline""#),
    // The bevel chrome (K80): line width and how far content moves while pressed.
    k("bevel.width", Int(1, 4), "1"),
    k("bevel.press_offset", Int(0, 4), "1"),
    // Menus (tray menu, dock menu, launcher rows): row height, the highlight's shape, separators, corner.
    k("menu.row", Int(0, 64), "0"),
    k(
        "menu.highlight",
        Choice(&["capsule", "bar", "inset"]),
        r#""capsule""#,
    ),
    k(
        "menu.separator",
        Choice(&["line", "etched", "space"]),
        r#""line""#,
    ),
    k("menu.radius", Int(-1, 24), "-1"),
    // The highlighted row's fill and text roles ("" = the caller's selection colours): 9x's navy band with white text.
    k("menu.fill", Role, r#""""#),
    k("menu.on", Role, r#""""#),
    // W53.5: room (px) a menu row keeps at its start for the look's cursor (snes's hand); callers indent their content by it.
    k("menu.lead", Int(0, 64), "0"),
    // Scroll bars: width, arrow buttons, the thumb's face.
    k("scroll.width", Int(0, 24), "0"),
    k("scroll.arrows", Bool, "false"),
    k(
        "scroll.thumb",
        Choice(&["pill", "flat", "bevel", "gel"]),
        r#""pill""#,
    ),
    // Tooltips: fill and text roles, a balloon's tail.
    k("tooltip.fill", Role, r#""""#),
    k("tooltip.on", Role, r#""""#),
    k("tooltip.tail", Bool, "false"),
    // W53.2: a tooltip's corner and border role (XP's and 7's balloon tips; -1 / "" = the part's own).
    k("tooltip.radius", Int(-1, 16), "-1"),
    k("tooltip.border", Role, r#""""#),
    // The tray well and separators between bar groups.
    k("tray.sunken", Bool, "false"),
    // The bar's groups: a raised block round each (`block`, today's) or none, one strip (`none`: 98's taskbar, whose
    // only well is the tray's) — contract row 596.
    k("bar.group", Choice(&["block", "none"]), r#""block""#),
    k(
        "separator.style",
        Choice(&["line", "etched", "none"]),
        r#""line""#,
    ),
    // Keyboard focus (FocusRing): style, offset (negative = inside), width.
    k(
        "focus.style",
        Choice(&["ring", "dotted", "double", "halo"]),
        r#""ring""#,
    ),
    k("focus.offset", Int(-8, 8), "0"),
    k("focus.width", Int(1, 4), "1"),
    // The ring's colour ("" = the accent, today's): Windows 11's focus visual is primary text, not the accent (W53.3).
    k("focus.color", Role, r#""""#),
    // The start button's dress shows its label beside the mark.
    k("start.label", Bool, "false"),
    // W53.2: the start button's fill (one role solid, two a gradient; [] = the part's own), the label's face (published
    // as `font.start`), size (0 = the part's own) and slant (XP's italic "start").
    k("start.fill", Roles, "[]"),
    k("start.family", Families, "[]"),
    k("start.size", Int(0, 32), "0"),
    k("start.italic", Bool, "false"),
    // W53.2: the tray well's fill ("" = the part's own): XP's lighter blue notification area.
    k("tray.fill", Role, r#""""#),
    // W53.2, the `bar` slot (a part drawn as the bar's ground, under its groups): its fill (one role solid, two a
    // gradient; [] = the part's own), the screen-facing edge's light line ("" = the part's own) and a gloss over the band
    // (XP's taskbar). `bar.group` (above, row 596) says whether the groups keep their blocks over it.
    k("bar.fill", Roles, "[]"),
    k("bar.edge", Role, r#""""#),
    k("bar.gloss", Num(0.0, 1.0), "0.0"),
    // Type: bitmap text (no smoothing, sizes on a grid of `pixel_step` px).
    k("type.pixel", Bool, "false"),
    k("type.pixel_step", Int(1, 16), "1"),
    // Symbols: the style's own icon font (ligature names as Material Symbols), the default icon size (0 = body + 4) and
    // a scale for every icon, the fill and weight (-1 = the chrome's).
    k("icons.family", Families, "[]"),
    // Cursor personality (W53.0b, I317; both off unless the user turns `cursor.theme` / `cursor.decoration` on): the
    // style's cursor set and the decoration `cursor.decoration = style` draws.
    k("cursor", Name, r#""""#),
    k(
        "cursor_decoration",
        Choice(&["", "trail", "sparkles", "ring"]),
        r#""""#,
    ),
    k("icon.size", Int(0, 64), "0"),
    k("icon.scale", Num(0.5, 2.0), "1.0"),
    k("icon.fill", Int(-1, 1), "-1"),
    k("icon.weight", Int(-1, 900), "-1"),
    // Motion personality (on top of K74's profiles; reduce motion still wins): the form surfaces move in, the stepped
    // style's hold (frames at 60 Hz per step), the timed durations (0 = K74's) and curves ([] = K74's).
    k(
        "motion.style",
        Choice(&["grow", "slide", "zoom", "fade", "flip", "stepped", "rubber"]),
        r#""grow""#,
    ),
    k("motion.steps", Int(1, 30), "4"),
    k("motion.open_ms", Int(0, 2000), "0"),
    k("motion.close_ms", Int(0, 2000), "0"),
    k("motion.fast_ms", Int(0, 2000), "0"),
    k("motion.effects_ms", Int(0, 2000), "0"),
    k("motion.open_curve", Curve, "[]"),
    k("motion.close_curve", Curve, "[]"),
    k("motion.fast_curve", Curve, "[]"),
    k("motion.effects_curve", Curve, "[]"),
    // Materials next to blur: a glow round blocks (its role and reach), a bloom of the block's own colour, a glossy sheen
    // on the upper half (Vista/7). 0 = none; static, nothing runs per frame.
    k("material.glow", Num(0.0, 1.0), "0.0"),
    k("material.glow_color", Role, r#""accent""#),
    k("material.glow_radius", Int(0, 48), "12"),
    k("material.bloom", Num(0.0, 1.0), "0.0"),
    k("material.bloom_radius", Int(0, 48), "16"),
    k("material.sheen", Num(0.0, 1.0), "0.0"),
    // The pixel grid (snes): positions and lines snap to it; 0 = none.
    k("pixel", Int(0, 8), "0"),
    // W53.3: the small and middle corner radii as fractions of the look's radius (`theme.shape.radius`, the large step):
    // K74's thirds by default; Windows 11's 4 px controls in 8 px flyouts are 0.5. A user's radius pin scales them all.
    k("shape.sm", Num(0.0, 1.0), "0.3333"),
    k("shape.md", Num(0.0, 1.0), "0.6667"),
    // W53.3: the window list's marks — `focused` (today's: the focused window's accent bar) or `pill` (every window a
    // short pill in the secondary ink, the focused one long in the accent: Windows 11's running and active indicators).
    k("task.mark", Choice(&["focused", "pill"]), r#""focused""#),
    // W53.3: the start menu's apps as a grid of this many columns while its field is empty (11's pinned grid and its
    // recommended rows); 0 = the launcher's rows.
    k("start.grid", Int(0, 8), "0"),
    // W53.3: where the start menu stands — at its start button (`button`, 9x/XP/7) or centred over the output (11).
    k("start.menu", Choice(&["button", "center"]), r#""button""#),
    // W53.3: the bar clock's lines on a horizontal bar — 1 (today's) or 2: the time over the date (7–11's taskbar clock).
    k("clock.lines", Int(1, 2), "1"),
    // W53.3: the share of the soft chrome's shadow a block casts (1 = today's; 0 = flat controls, the surfaces keep their
    // elevation) and the corner of the quick settings' tiles (-1 = a pill, today's).
    k("chrome.soft_scale", Num(0.0, 1.0), "1.0"),
    k("tile.radius", Int(-1, 24), "-1"),
    // W53.3 (lead review): the quick settings card's chrome — a phone (K42, today's) or a plain flyout of the panel's
    // material — and its tiles: wide pills in two columns (today's) or compact buttons in three, the label under them.
    k("quick.frame", Choice(&["phone", "flyout"]), r#""phone""#),
    k("quick.tiles", Choice(&["wide", "compact", "rows"]), r#""wide""#),
    // W53.5: `rows` (a config screen: one row per switch, the label at the left and its value at the right) shows the
    // value as both words with the chosen one lit (`pair`: 16-bit RPG configs' "ON  OFF") or as the chosen word (`value`:
    // the PS2's System Configuration).
    k("quick.values", Choice(&["pair", "value"]), r#""value""#),
    // The right sidebar's form: one column (today's) or, while it floats, its sections as separate flyouts stacked at its
    // foot (11's notification centre over its calendar); the calendar's days as boxed keys (today's) or flat, today a circle.
    k("centre.form", Choice(&["column", "flyouts"]), r#""column""#),
    k("calendar.cells", Choice(&["boxed", "flat"]), r#""boxed""#),
    // Where toasts stand under a top or bottom bar: out of the island (W34, today's) or in the screen's corner at the
    // bar's end, stacked (11's bottom-right).
    k("toast.place", Choice(&["island", "corner", "bottom"]), r#""island""#),
    // W53.5: `bottom` — one wide box centred low on the screen, over a bottom bar (an RPG's text box, the PS2's low line).
    // The gap between a horizontal bar's modules and groups, px (-1 = today's: the pad and the groups' insets).
    k("bar.gap", Int(-1, 32), "-1"),
    // W53.5 (snes, ps2; any look): a card's fill in this many hard bands, top to bottom from `fill.band_top` to
    // `fill.band_bottom` (roles; "" = the container lighter / darker) — 16-bit windows' banded gradient (0 = one fill).
    k("fill.bands", Int(0, 16), "0"),
    // Each band this tall instead (grid pixels on a pixel grid, else px; 0 = `fill.bands` bands): FF6's 5-row bands.
    k("fill.band_h", Int(0, 64), "0"),
    k("fill.band_top", Role, r#""""#),
    k("fill.band_bottom", Role, r#""""#),
    // W53.5: the island's line types itself out once when its face changes (`type`: an RPG text box), at this many
    // characters a second; reduce motion shows it whole.
    k("island.reveal", Choice(&["none", "type"]), r#""none""#),
    k("island.reveal_cps", Int(5, 240), "40"),
    // W53.5: a text field as a box (today's) or a line under the text (`underline`: a name-entry line, the PS2's field).
    k("field.form", Choice(&["box", "underline"]), r#""box""#),
    // W53.5: what loading shows — the caller's words (`text`, today's), the look's loading line with dots stepping after
    // it (`dots`: "NOW LOADING..."), or the words under a slow pulse (`pulse`). Only while loading.
    k("loading.form", Choice(&["text", "dots", "pulse"]), r#""text""#),
    // W53.5: the regular text weight (bold stays 300 heavier, at most 900): thin type as the PS2's (Light, 300).
    k("type.weight", Int(100, 900), "400"),
    // W53.5: the launcher and the island's cards grow out of the bar as one shape (true, W21's morph) or stand apart from
    // it as windows of their own (false: a 16-bit RPG window, a PS2 panel), drawn as blocks with the look's frame.
    k("surface.join", Bool, "true"),
];

/// The `[decor]` key named `key`.
pub fn decor_key(key: &str) -> Option<&'static DecorKey> {
    DECOR_KEYS.iter().find(|d| d.key == key)
}

impl DecorKey {
    pub fn default_value(&self) -> Value {
        serde_json::from_str(self.default).expect("DECOR_KEYS defaults are JSON")
    }

    /// `v` as this key takes it (an integer for an integer key given as `18.0`), or `None` when it is not one.
    pub fn check(&self, v: &Value) -> Option<Value> {
        let role = |r: &Value| {
            r.as_str()
                .is_some_and(|s| crate::palette::ROLES.contains(&s))
        };
        match self.kind {
            Int(lo, hi) => {
                let f = v.as_f64()?;
                (f.fract() == 0.0 && f >= lo as f64 && f <= hi as f64)
                    .then(|| Value::from(f as i64))
            }
            Num(lo, hi) => {
                let f = v.as_f64()?;
                (lo..=hi).contains(&f).then(|| Value::from(f))
            }
            Bool => v.is_boolean().then(|| v.clone()),
            Choice(c) => v
                .as_str()
                .is_some_and(|s| c.contains(&s))
                .then(|| v.clone()),
            Role => (v.as_str() == Some("") || role(v)).then(|| v.clone()),
            Roles => {
                let a = v.as_array()?;
                ((1..=2).contains(&a.len()) && a.iter().all(role)).then(|| v.clone())
            }
            Curve => {
                let n: Vec<f64> = v
                    .as_array()?
                    .iter()
                    .map(Value::as_f64)
                    .collect::<Option<_>>()?;
                let ok = match n.len() {
                    0 | 4 => true,
                    l if l % 6 == 0 => n[l - 2] == 1.0 && n[l - 1] == 1.0,
                    _ => false,
                };
                // x stays within the animation's 0..1; y may overshoot.
                let xs_ok = n.chunks(2).all(|p| (0.0..=1.0).contains(&p[0]));
                (ok && xs_ok && n.iter().all(|f| f.is_finite())).then(|| v.clone())
            }
            Families => {
                let a = v.as_array()?;
                a.iter()
                    .all(|f| f.as_str().is_some_and(|s| !s.is_empty()))
                    .then(|| v.clone())
            }
            Name => {
                let s = v.as_str()?;
                (s.len() <= 64
                    && s.chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-'))
                .then(|| v.clone())
            }
        }
    }
}

/// The keys a look sets, and picking a look resets: its form and feel.
pub const LOOK_KEYS: &[&str] = &[
    "theme.chrome",
    "theme.shape.corners",
    "theme.shape.radius",
    "theme.shape.squircle",
    "theme.outline_ink",
    "theme.material.kind",
    "theme.material.opacity",
    "theme.material.blur",
    "theme.motion.profile",
    "theme.motion.speed",
    "theme.typography.family",
    "theme.typography.family_jp",
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.texture.depth",
    "theme.texture.shadows",
    "theme.texture.cracks",
    "theme.texture.crack_style",
    "theme.pen.line",
    "theme.pen.pressure",
    "theme.pen.breaks",
    "theme.pen.fade",
    "theme.pen.wobble",
];

/// The material keys a look or style sets (K59): the user's own come back with `theme.texture.restore`.
pub const TEXTURE_KEYS: &[&str] = &[
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.texture.depth",
    "theme.texture.shadows",
    "theme.texture.cracks",
    "theme.texture.crack_style",
];

/// The keys applying a style resets: its look and palette, light or dark, every look key and the density. Applying a
/// style makes light or dark follow it (K55: the user's own mode before it is kept by the daemon, one click brings it
/// back). Accessibility preferences (contrast, colour-blind shift, text scale, pure black), the seasonal tint, the
/// screen corners and the app export are the user's: they stay.
pub const STYLE_KEYS: &[&str] = &[
    "theme.look",
    "theme.colors.palette",
    "theme.colors.scheme",
    "theme.density",
    "theme.chrome",
    "theme.shape.corners",
    "theme.shape.radius",
    "theme.shape.squircle",
    "theme.outline_ink",
    "theme.material.kind",
    "theme.material.opacity",
    "theme.material.blur",
    "theme.motion.profile",
    "theme.motion.speed",
    "theme.typography.family",
    "theme.typography.family_jp",
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.colors.ink",
];

/// The categories Settings groups packs by, in its order. A pack naming another one is `custom`.
pub const CATEGORIES: &[&str] = &["modern", "inspired", "retro", "fiction", "custom"];

const BUNDLED_LOOKS: &[(&str, &str)] = &[
    ("kanso", include_str!("../../../looks/kanso.toml")),
    ("soft", include_str!("../../../looks/soft.toml")),
    ("glass", include_str!("../../../looks/glass.toml")),
    ("material", include_str!("../../../looks/material.toml")),
    ("terminal", include_str!("../../../looks/terminal.toml")),
    ("washi", include_str!("../../../looks/washi.toml")),
    ("kami", include_str!("../../../looks/kami.toml")),
    ("sekai", include_str!("../../../looks/sekai.toml")),
    ("aqua", include_str!("../../../looks/aqua.toml")),
    // W25 identity looks, after shellseikatsu's `Services/Modes/*.qml` presets.
    ("win95", include_str!("../../../looks/win95.toml")),
    ("luna", include_str!("../../../looks/luna.toml")),
    ("aero", include_str!("../../../looks/aero.toml")),
    ("fluent", include_str!("../../../looks/fluent.toml")),
    ("ps2", include_str!("../../../looks/ps2.toml")),
    ("snes", include_str!("../../../looks/snes.toml")),
    ("kawaii", include_str!("../../../looks/kawaii.toml")),
    ("yorha", include_str!("../../../looks/yorha.toml")),
    ("hallownest", include_str!("../../../looks/hallownest.toml")),
    ("souls", include_str!("../../../looks/souls.toml")),
];

const BUNDLED_STYLES: &[(&str, &str)] = &[
    ("washi", include_str!("../../../styles/washi.toml")),
    ("kami", include_str!("../../../styles/kami.toml")),
    ("kanso", include_str!("../../../styles/kanso.toml")),
    ("material", include_str!("../../../styles/material.toml")),
    ("glass", include_str!("../../../styles/glass.toml")),
    ("terminal", include_str!("../../../styles/terminal.toml")),
    ("sekai", include_str!("../../../styles/sekai.toml")),
    ("aqua", include_str!("../../../styles/aqua.toml")),
    ("win95", include_str!("../../../styles/win95.toml")),
    ("luna", include_str!("../../../styles/luna.toml")),
    ("aero", include_str!("../../../styles/aero.toml")),
    ("fluent", include_str!("../../../styles/fluent.toml")),
    ("ps2", include_str!("../../../styles/ps2.toml")),
    ("snes", include_str!("../../../styles/snes.toml")),
    ("kawaii", include_str!("../../../styles/kawaii.toml")),
    ("yorha", include_str!("../../../styles/yorha.toml")),
    (
        "hallownest",
        include_str!("../../../styles/hallownest.toml"),
    ),
    ("souls", include_str!("../../../styles/souls.toml")),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Look,
    Style,
}

impl Kind {
    fn dir(self) -> &'static str {
        match self {
            Kind::Look => "looks",
            Kind::Style => "styles",
        }
    }

    /// Whether a recipe of this kind may set `key`. A style's look keys are tweaks of its own look (see [`layer`]).
    fn allows(self, key: &str) -> bool {
        match self {
            Kind::Look => LOOK_KEYS.contains(&key),
            Kind::Style => {
                STYLE_KEYS.contains(&key) && key != "theme.look" && key != "theme.colors.palette"
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Pack {
    pub kind: Kind,
    pub name: String,
    /// An i18n key or plain text.
    pub label: String,
    /// One of [`CATEGORIES`].
    pub category: String,
    pub recipe: Vec<(String, Value)>,
    /// Recipe keys that were dropped (not this kind's).
    pub refused: Vec<String>,
    pub bundled: bool,
    /// Looks: `[slots] frame`, the frame component the frontend draws over blocks; `""` for none.
    pub frame: String,
    /// Looks: every `[slots]` entry (W53.0a), `frame` included; a slot left out is the default.
    pub slots: BTreeMap<String, String>,
    /// Looks: the `[decor]` metrics (W53.0a), checked against [`DECOR_KEYS`].
    pub decor: BTreeMap<String, Value>,
    /// Styles: the look and the palette they are made of.
    pub look: String,
    pub palette: String,
}

fn slug_ok(s: &str) -> bool {
    s.chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// Parses one pack file; `fallback_name` when it names none.
pub fn parse(kind: Kind, src: &str, fallback_name: &str, bundled: bool) -> Result<Pack, String> {
    let v: toml::Value = toml::from_str(src).map_err(|e| e.to_string())?;
    let text = |k: &str| v.get(k).and_then(toml::Value::as_str);
    let name = text("name").unwrap_or(fallback_name).to_owned();
    if name.is_empty() || name == "none" || !slug_ok(&name) {
        return Err(format!("{} name {name:?} is not allowed", kind.dir()));
    }
    let prefix = match kind {
        Kind::Look => "look",
        Kind::Style => "style",
    };
    let label =
        text("label").map_or_else(|| format!("config.choice.{prefix}.{name}"), String::from);
    let category = text("category")
        .filter(|c| CATEGORIES.contains(c))
        .unwrap_or("custom")
        .to_owned();
    let mut recipe = Vec::new();
    let mut refused = Vec::new();
    if let Some(t) = v.get("recipe").and_then(toml::Value::as_table) {
        for (k, val) in t {
            if !kind.allows(k) {
                refused.push(k.clone());
                continue;
            }
            recipe.push((
                k.clone(),
                serde_json::to_value(val).map_err(|e| e.to_string())?,
            ));
        }
    }
    // Schema v7 (I297): a pack file has no schema version to migrate, so a user's pack that still says `glass` reads as
    // what glass was — translucent with its blur on (unless it says otherwise).
    if let Some(e) = recipe
        .iter_mut()
        .find(|(k, v)| k == "theme.material.kind" && v == "glass")
    {
        e.1 = serde_json::Value::from("translucent");
        if !recipe.iter().any(|(k, _)| k == "theme.material.blur") {
            recipe.push(("theme.material.blur".into(), serde_json::Value::Bool(true)));
        }
    }
    // A slot names a QML file: lowercase words joined by `-`, nothing that could leave its directory. Only looks carry
    // slots and decor (a style dresses with its look's).
    let mut slots = BTreeMap::new();
    if let Some(t) = v.get("slots").and_then(toml::Value::as_table) {
        for (slot, val) in t {
            let name = val.as_str().unwrap_or_default();
            if !slug_ok(name) || val.as_str().is_none() || (kind == Kind::Style && !name.is_empty())
            {
                return Err(format!("{} {slot} {val} is not allowed", kind.dir()));
            }
            if !SLOTS.contains(&slot.as_str()) {
                refused.push(format!("slots.{slot}"));
                continue;
            }
            slots.insert(slot.clone(), name.to_owned());
        }
    }
    let frame = slots.get("frame").cloned().unwrap_or_default();
    let mut decor = BTreeMap::new();
    if let Some(t) = v.get("decor").and_then(toml::Value::as_table) {
        if kind == Kind::Style {
            return Err("styles have no [decor]: their look's applies".into());
        }
        let mut flat = Vec::new();
        flatten_decor("", t, &mut flat);
        for (key, val) in flat {
            let val = serde_json::to_value(val).map_err(|e| e.to_string())?;
            match decor_key(&key).and_then(|d| d.check(&val)) {
                Some(ok) => {
                    decor.insert(key, ok);
                }
                None => refused.push(format!("decor.{key}")),
            }
        }
    }
    let (look, palette) = match kind {
        Kind::Look => (String::new(), String::new()),
        Kind::Style => {
            let look = text("look").unwrap_or("kanso");
            let palette = text("palette").unwrap_or("wa-iro");
            if !slug_ok(look) || look.is_empty() {
                return Err(format!("style look {look:?} is not allowed"));
            }
            (look.to_owned(), palette.to_owned())
        }
    };
    Ok(Pack {
        kind,
        name,
        label,
        category,
        recipe,
        refused,
        bundled,
        frame,
        slots,
        decor,
        look,
        palette,
    })
}

/// `[decor]` with nested tables (`[decor.title] height = 18`) flattened to dotted keys (`title.height`).
fn flatten_decor(prefix: &str, t: &toml::Table, out: &mut Vec<(String, toml::Value)>) {
    for (k, v) in t {
        let key = if prefix.is_empty() {
            k.clone()
        } else {
            format!("{prefix}.{k}")
        };
        match v.as_table() {
            Some(sub) => flatten_decor(&key, sub, out),
            None => out.push((key, v.clone())),
        }
    }
}

impl Pack {
    /// The decor this look dresses the shell in (W53.0a): its slots and metrics, for [`crate::ThemeInput::decor`].
    pub fn decor_input(&self) -> crate::Decor {
        crate::Decor {
            slots: self.slots.clone(),
            metrics: self.decor.clone(),
        }
    }
}

/// `$XDG_CONFIG_HOME/kurashi/<looks|styles>` (or `~/.config/…`).
pub fn user_dir(kind: Kind) -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .map(|c| c.join("kurashi").join(kind.dir()))
}

/// Every pack of a kind: the bundled ones in their order, then the ones in `dirs` (a pack of the same name replaces
/// the bundled one in place). Unreadable or invalid files are skipped with a warning.
pub fn all_in(kind: Kind, dirs: &[PathBuf]) -> Vec<Pack> {
    let bundled = match kind {
        Kind::Look => BUNDLED_LOOKS,
        Kind::Style => BUNDLED_STYLES,
    };
    let mut out: Vec<Pack> = bundled
        .iter()
        .filter_map(|(n, src)| parse(kind, src, n, true).ok())
        .collect();
    for dir in dirs {
        let Ok(rd) = std::fs::read_dir(dir) else {
            continue;
        };
        let mut files: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "toml"))
            .collect();
        files.sort();
        for f in files {
            let stem = f
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_owned();
            match std::fs::read_to_string(&f)
                .map_err(|e| e.to_string())
                .and_then(|s| parse(kind, &s, &stem, false))
            {
                Ok(d) => match out.iter_mut().find(|x| x.name == d.name) {
                    Some(slot) => *slot = d,
                    None => out.push(d),
                },
                Err(e) => warn(&f, &e),
            }
        }
    }
    out
}

fn warn(path: &Path, e: &str) {
    eprintln!("kurashi-theme: {} skipped: {e}", path.display());
}

/// The packs the daemon offers: bundled + the user's.
pub fn all(kind: Kind) -> Vec<Pack> {
    all_in(kind, &user_dir(kind).into_iter().collect::<Vec<_>>())
}

pub fn find(kind: Kind, name: &str) -> Option<Pack> {
    all(kind).into_iter().find(|d| d.name == name)
}

/// One entry of the `theme:<source>` layer: the key, its value and the source it names (`style:<name>`,
/// `look:<name>`), so provenance says which pack recommended it.
pub type LayerEntry = (String, Value, String);

/// The theme layer (K53) for the active style (if any) and the look in effect: the look's recipe, then the style's
/// look and palette and its own recipe on top. A style's tweaks of look keys apply only while its own look is the one
/// in effect — a look the user picked over the style is that look, not the style's version of it.
pub fn layer(style: Option<&Pack>, look: Option<&Pack>) -> Vec<LayerEntry> {
    let mut out: Vec<LayerEntry> = Vec::new();
    let mut put = |k: &str, v: Value, src: String| match out.iter_mut().find(|e| e.0 == k) {
        Some(e) => *e = (k.to_owned(), v, src),
        None => out.push((k.to_owned(), v, src)),
    };
    if let Some(l) = look {
        for (k, v) in &l.recipe {
            put(k, v.clone(), format!("look:{}", l.name));
        }
    }
    if let Some(s) = style {
        let src = format!("style:{}", s.name);
        put("theme.look", Value::String(s.look.clone()), src.clone());
        put(
            "theme.colors.palette",
            Value::String(s.palette.clone()),
            src.clone(),
        );
        let own_look = look.is_some_and(|l| l.name == s.look);
        for (k, v) in &s.recipe {
            if LOOK_KEYS.contains(&k.as_str()) && !own_look {
                continue;
            }
            put(k, v.clone(), src.clone());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_file(frame: &str) -> PathBuf {
        let file: String = frame
            .split('-')
            .map(|w| {
                let mut c = w.chars();
                c.next()
                    .map(|f| f.to_ascii_uppercase().to_string() + c.as_str())
                    .unwrap_or_default()
            })
            .collect();
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../frontend/components/frames")
            .join(format!("{file}.qml"))
    }

    #[test]
    fn bundled_packs_parse_and_keep_to_their_kind() {
        let looks = all_in(Kind::Look, &[]);
        let styles = all_in(Kind::Style, &[]);
        assert_eq!(looks.len(), BUNDLED_LOOKS.len());
        assert_eq!(styles.len(), BUNDLED_STYLES.len());
        assert_eq!(styles[0].name, "washi");
        let palettes = crate::bundled_names();
        for d in looks.iter().chain(&styles) {
            assert!(d.refused.is_empty(), "{} refuses {:?}", d.name, d.refused);
            assert_ne!(d.category, "custom", "{} has no category", d.name);
            if !d.frame.is_empty() {
                assert!(
                    frame_file(&d.frame).is_file(),
                    "{}: frame {}",
                    d.name,
                    d.frame
                );
            }
        }
        for l in &looks {
            assert!(!l.recipe.is_empty(), "{}", l.name);
            // A look is colourless (K53).
            assert!(
                l.recipe
                    .iter()
                    .all(|(k, _)| !k.starts_with("theme.colors.")),
                "{}",
                l.name
            );
        }
        for s in &styles {
            assert!(
                palettes.contains(&s.palette.as_str()),
                "{}: palette {}",
                s.name,
                s.palette
            );
            assert!(
                looks.iter().any(|l| l.name == s.look),
                "{}: look {}",
                s.name,
                s.look
            );
        }
        assert_eq!(
            looks.iter().find(|d| d.name == "yorha").unwrap().frame,
            "yorha"
        );
        assert_eq!(looks.iter().find(|d| d.name == "sekai").unwrap().frame, "");
        assert!(parse(Kind::Look, "[slots]\nframe = \"../x\"\n", "x", false).is_err());
        assert!(parse(Kind::Style, "[slots]\nframe = \"x\"\n", "x", false).is_err());
    }

    #[test]
    fn a_pack_that_says_glass_reads_as_translucent_with_blur() {
        let get = |p: &Pack, k: &str| {
            p.recipe
                .iter()
                .find(|(n, _)| n == k)
                .map(|(_, v)| v.clone())
        };
        let p = parse(
            Kind::Look,
            "name = \"mine\"\n[recipe]\n\"theme.material.kind\" = \"glass\"\n",
            "x",
            false,
        )
        .unwrap();
        assert_eq!(get(&p, "theme.material.kind"), Some("translucent".into()));
        assert_eq!(get(&p, "theme.material.blur"), Some(true.into()));
        // Its own blur switch stays.
        let p = parse(
            Kind::Look,
            "name = \"mine\"\n[recipe]\n\"theme.material.kind\" = \"glass\"\n\"theme.material.blur\" = false\n",
            "x",
            false,
        )
        .unwrap();
        assert_eq!(get(&p, "theme.material.blur"), Some(false.into()));
    }

    #[test]
    fn foreign_keys_are_refused_and_user_packs_replace_bundled_ones() {
        let d = parse(
            Kind::Look,
            "name = \"mine\"\n[recipe]\n\"theme.chrome\" = \"line\"\n\"bar.height\" = 40\n\"theme.colors.palette\" = \"x\"\n",
            "x",
            false,
        )
        .unwrap();
        assert_eq!(d.recipe.len(), 1);
        assert_eq!(d.refused, ["bar.height", "theme.colors.palette"]);
        assert_eq!(d.category, "custom");
        let s = parse(
            Kind::Style,
            "look = \"sekai\"\npalette = \"kanso\"\n[recipe]\n\"theme.density\" = \"compact\"\n\"theme.look\" = \"x\"\n\"bar.edge\" = \"left\"\n",
            "mine",
            false,
        )
        .unwrap();
        assert_eq!((s.look.as_str(), s.palette.as_str()), ("sekai", "kanso"));
        assert_eq!(s.refused, ["bar.edge", "theme.look"]);
        assert!(parse(Kind::Look, "name = \"none\"", "none", false).is_err());
        let dir = std::env::temp_dir().join(format!("kurashi-looks-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("sekai.toml"),
            "[recipe]\n\"theme.chrome\" = \"flat\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("zen.toml"),
            "label = \"Zen\"\n[recipe]\n\"theme.chrome\" = \"line\"\n",
        )
        .unwrap();
        let all = all_in(Kind::Look, std::slice::from_ref(&dir));
        let sekai = all.iter().find(|d| d.name == "sekai").unwrap();
        assert!(!sekai.bundled && sekai.recipe.len() == 1);
        assert_eq!(all.last().unwrap().label, "Zen");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_styles_look_tweaks_apply_to_its_own_look_only() {
        let style = parse(
            Kind::Style,
            "name = \"cozy\"\nlook = \"soft\"\npalette = \"catppuccin\"\n[recipe]\n\"theme.shape.radius\" = 23\n\"theme.density\" = \"airy\"\n",
            "cozy",
            false,
        )
        .unwrap();
        let soft = find(Kind::Look, "soft").unwrap();
        let sekai = find(Kind::Look, "sekai").unwrap();
        let get = |l: &[LayerEntry], k: &str| {
            l.iter()
                .find(|e| e.0 == k)
                .map(|e| (e.1.clone(), e.2.clone()))
        };
        let own = layer(Some(&style), Some(&soft));
        assert_eq!(
            get(&own, "theme.shape.radius").unwrap(),
            (serde_json::json!(23), "style:cozy".into())
        );
        assert_eq!(get(&own, "theme.chrome").unwrap().1, "look:soft");
        assert_eq!(get(&own, "theme.look").unwrap().0, "soft");
        // The user picked sekai over the style: sekai's own corners, the style's density and palette still.
        let over = layer(Some(&style), Some(&sekai));
        assert_eq!(
            get(&over, "theme.shape.radius").unwrap(),
            (serde_json::json!(23), "look:sekai".into())
        );
        assert_eq!(get(&over, "theme.density").unwrap().1, "style:cozy");
        assert_eq!(get(&over, "theme.colors.palette").unwrap().0, "catppuccin");
        // No style: the look alone.
        assert!(get(&layer(None, Some(&sekai)), "theme.colors.palette").is_none());
    }
}
