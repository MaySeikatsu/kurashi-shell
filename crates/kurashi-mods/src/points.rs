//! The shell's extension points (K154, MODS.md "Integration contract"): the one list of where a mod can stand. The
//! manifest validator, `runtime.slots`, MODS.md's table, `kurashi mod check`'s variant rule and the Mod Editor's
//! checklist all read it (rule 3); a test holds the shell's `SlotHost { slot: … }` names to it.

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PointKind {
    /// A variant of a placeable module (K72): one manifest `provides` kind each.
    Variant,
    /// A named slot of a core view (K28), filled with `slot:<id>`.
    Slot,
    /// A menu of the shell a mod adds rows to with `[[menu]] at = "<id>"`.
    Menu,
    /// Something the mod is reached by rather than drawn in: a `>` command, a launcher provider, a settings page.
    Reach,
    /// Something the mod hands the core rather than shows: a place for `svc.location` (W92).
    Feed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Point {
    /// What a manifest names: a slot's or a menu's id, a variant's key (also the `[skips]` key).
    pub id: &'static str,
    pub kind: PointKind,
    /// How a manifest fills it.
    pub fill: &'static str,
    /// Where it shows and what the host hands the contribution.
    pub about: &'static str,
    /// Whether a mod that provides a placeable module (`widget:`) must ship it or say why not (`[skips]`).
    pub expected: bool,
}

const fn point(
    id: &'static str,
    kind: PointKind,
    fill: &'static str,
    about: &'static str,
    expected: bool,
) -> Point {
    Point {
        id,
        kind,
        fill,
        about,
        expected,
    }
}

use PointKind::{Feed, Menu, Reach, Slot, Variant};

/// Every extension point, in the order the docs and the editor list them.
pub const POINTS: &[Point] = &[
    point(
        "glance",
        Variant,
        "widget:<name>",
        "A module in a bar or an edge zone (`qml/Widget.qml`): its short form; `vertical`, `compact`, `room` are set by the bar",
        true,
    ),
    point(
        "peek",
        Variant,
        "peek:<name>",
        "The card under the module on hover or focus (`qml/Peek.qml`, K35)",
        true,
    ),
    point(
        "panel",
        Variant,
        "panel:<name>",
        "The expanded view: a Stage card, a sidebar section, a web dock view (`qml/Panel.qml`); `fillHeight`, `placement`, `cardPlacement`, `cardLarge`",
        true,
    ),
    point(
        "desk",
        Variant,
        "desk:<name>",
        "A card on the desktop's widget column (`qml/desk/<name>.qml`, K46); it takes the column's width",
        true,
    ),
    point(
        "island-face",
        Variant,
        "island-face:<name>",
        "A face of the Island with its expanded view (`qml/Face.qml`, `qml/FaceExpanded.qml`); raised through `ModCtx::face`",
        true,
    ),
    point(
        "quick-tile",
        Variant,
        "slot:quick.tiles",
        "A tile in quick settings (`qml/slots/quick.tiles.qml`)",
        true,
    ),
    point(
        "command",
        Reach,
        "[[action]] command = \"<word>\"",
        "A `>` command in the launcher, listed by `kurashi act --list`, offered to key binds",
        true,
    ),
    point(
        "menu",
        Reach,
        "[[menu]] at = \"module\"",
        "Rows in the module's own menu (right-click on its glance, its desk card, its panel's header)",
        true,
    ),
    point(
        "settings",
        Reach,
        "[[setting]]",
        "A page of its own in Settings, generated from its settings: labels, controls, defaults, provenance",
        false,
    ),
    point(
        "launcher",
        Reach,
        "launcher:<name>",
        "A launcher provider with an optional prefix (K150): rows that run the mod's own actions",
        false,
    ),
    point(
        "location",
        Feed,
        "location:<name>",
        "A place the mod knows (`ModCtx::location`): the shell's `svc.location` carries it while no place is set by hand — the night light's sun schedule and the light's daytime read it",
        false,
    ),
    point(
        "surface",
        Variant,
        "surface:<name>",
        "A layer-shell surface of the mod's own, one per output (`qml/surfaces/<name>.qml`)",
        false,
    ),
    point(
        "clock.expanded.aside",
        Slot,
        "slot:clock.expanded.aside",
        "Beside the clock view's month, 140 px wide",
        false,
    ),
    point(
        "clock.expanded.day",
        Slot,
        "slot:clock.expanded.day",
        "Under the month: the chosen day (`extra.date`)",
        false,
    ),
    point(
        "clock.expanded.daymark",
        Slot,
        "slot:clock.expanded.daymark",
        "One mark per date in the month grid, instantiated per visible day cell (row 71)",
        false,
    ),
    point(
        "clock.expanded.footer",
        Slot,
        "slot:clock.expanded.footer",
        "Under the clock view, its full width",
        false,
    ),
    point(
        "media.expanded.below",
        Slot,
        "slot:media.expanded.below",
        "Under the media view's transport, its full width",
        false,
    ),
    point(
        "media.expanded.backdrop",
        Slot,
        "slot:media.expanded.backdrop",
        "Behind the media view, filling it",
        false,
    ),
    point(
        "notifications.expanded.header",
        Slot,
        "slot:notifications.expanded.header",
        "Above the notification list",
        false,
    ),
    point(
        "quick.tiles",
        Slot,
        "slot:quick.tiles",
        "The quick settings' tile grid (the `quick-tile` variant)",
        false,
    ),
    point(
        "lock.aside",
        Slot,
        "slot:lock.aside",
        "Beside the lock screen's clock",
        false,
    ),
    point(
        "module",
        Menu,
        "[[menu]] at = \"module\"",
        "The mod's own module menu (the `menu` reach)",
        false,
    ),
    point(
        "desktop",
        Menu,
        "[[menu]] at = \"desktop\"",
        "The desktop's right-click menu; `output` is handed to the action",
        false,
    ),
    point(
        "bar",
        Menu,
        "[[menu]] at = \"bar\"",
        "A bar's background menu; `output` is handed to the action",
        false,
    ),
];

/// The core views' slot names (K28).
pub fn slots() -> impl Iterator<Item = &'static str> {
    POINTS.iter().filter(|p| p.kind == Slot).map(|p| p.id)
}

pub fn is_slot(id: &str) -> bool {
    slots().any(|s| s == id)
}

pub fn is_menu(id: &str) -> bool {
    POINTS.iter().any(|p| p.kind == Menu && p.id == id)
}

/// The points a mod with a placeable module answers for (K72), by their `[skips]` key.
pub fn expected() -> impl Iterator<Item = &'static Point> {
    POINTS.iter().filter(|p| p.expected)
}

pub fn get(id: &str) -> Option<&'static Point> {
    POINTS.iter().find(|p| p.id == id)
}

/// MODS.md's table (between its `points:begin` and `points:end` marks).
pub fn markdown() -> String {
    let mut out = String::from(
        "| Point | Kind | A manifest fills it with | Where, and what it is handed |\n|---|---|---|---|\n",
    );
    for p in POINTS {
        let kind = match p.kind {
            Variant => "variant",
            Slot => "slot",
            Menu => "menu",
            Reach => "reach",
            Feed => "feed",
        };
        let must = if p.expected { " ·" } else { "" };
        out.push_str(&format!(
            "| `{}`{must} | {kind} | `{}` | {} |\n",
            p.id, p.fill, p.about
        ));
    }
    out.push_str(
        "\n`·` = a mod that provides a placeable module ships it or names it in `[skips]`.\n",
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_per_kind_and_slots_are_dotted() {
        for (i, p) in POINTS.iter().enumerate() {
            assert!(
                !POINTS[..i].iter().any(|q| q.id == p.id && q.kind == p.kind),
                "{} twice",
                p.id
            );
            if p.kind == Slot {
                assert!(p.id.contains('.'), "{}", p.id);
            }
        }
        assert!(is_slot("quick.tiles") && !is_slot("glance"));
        assert!(is_menu("desktop") && !is_menu("quick.tiles"));
    }
}
