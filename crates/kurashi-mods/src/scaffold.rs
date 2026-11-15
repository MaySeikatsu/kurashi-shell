//! `kurashi mod new` (K154, MODS.md "Feeling native"): a mod written from templates that pass `kurashi mod check`
//! as they are — the manifest with its icon, every variant shipped or skipped with a reason, views on `qs.kit` and the
//! theme's tokens, copy in `i18n/{en,ja}.toml`. The CLI and the Mod Editor call the same code (rule 1, rule 3).
//!
//! What it writes needs no daemon code: a mod of views over documents it `uses`. An action, an island face or a
//! service of its own needs a crate in the shell's tree today (docs/MODDING.md "Routes").

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::contract::icon_ok;

/// What the scaffolder can write, by the name `--with` takes (a subset of `points::POINTS`' variants).
pub const PARTS: &[(&str, &str)] = &[
    ("widget", "the glance: a module in a bar or an edge zone"),
    ("peek", "the card under the module on hover or focus"),
    (
        "panel",
        "the expanded view: a Stage card and a sidebar section",
    ),
    ("desk", "a card on the desktop's widget column"),
    ("tile", "a tile in quick settings"),
    ("menu", "rows in the module's own menu"),
    ("settings", "a setting, shown on the mod's Settings page"),
];

#[derive(Debug, Clone, PartialEq)]
pub struct Spec {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub description: String,
    /// Names from [`PARTS`].
    pub with: Vec<String>,
    /// `uses` entries, as a manifest writes them.
    pub uses: Vec<String>,
}

#[derive(Debug, PartialEq, thiserror::Error)]
pub enum ScaffoldError {
    #[error("mods.new.error.id_invalid")]
    IdInvalid,
    #[error("mods.new.error.name_empty")]
    NameEmpty,
    #[error("mods.new.error.icon_invalid")]
    IconInvalid,
    #[error("mods.new.error.part_unknown: {0}")]
    PartUnknown(String),
    #[error("mods.new.error.nothing_chosen")]
    NothingChosen,
    #[error("mods.new.error.id_taken")]
    IdTaken,
    #[error("mods.new.error.write: {0}")]
    Write(String),
}

fn id_ok(s: &str) -> bool {
    (1..=32).contains(&s.len())
        && s.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn toml_str(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

impl Spec {
    fn has(&self, part: &str) -> bool {
        self.with.iter().any(|p| p == part)
    }

    pub fn validate(&self) -> Result<(), ScaffoldError> {
        if !id_ok(&self.id) || crate::manifest::RESERVED_IDS.contains(&self.id.as_str()) {
            return Err(ScaffoldError::IdInvalid);
        }
        if self.name.trim().is_empty() {
            return Err(ScaffoldError::NameEmpty);
        }
        if !icon_ok(&self.icon) {
            return Err(ScaffoldError::IconInvalid);
        }
        for p in &self.with {
            if !PARTS.iter().any(|(n, _)| n == p) {
                return Err(ScaffoldError::PartUnknown(p.clone()));
            }
        }
        if !["widget", "panel", "desk", "tile"]
            .iter()
            .any(|p| self.has(p))
        {
            return Err(ScaffoldError::NothingChosen);
        }
        Ok(())
    }

    /// The files of the mod, relative to its folder, in the order they are listed to the user.
    pub fn files(&self) -> Result<Vec<(PathBuf, String)>, ScaffoldError> {
        self.validate()?;
        let id = &self.id;
        let k = format!("mod-{id}");
        let mut out: Vec<(PathBuf, String)> = Vec::new();
        let mut en: BTreeMap<String, String> = BTreeMap::new();
        let mut ja: BTreeMap<String, String> = BTreeMap::new();
        let mut say = |key: &str, e: &str, j: &str| {
            en.insert(key.to_owned(), e.to_owned());
            ja.insert(key.to_owned(), j.to_owned());
        };
        say("description", &self.description, &self.description);
        say("name", &self.name, &self.name);
        say(
            "open",
            &format!("Open {}", self.name),
            &format!("{}を開く", self.name),
        );
        say(
            "hello",
            "Nothing here yet. This is where your view goes.",
            "まだ何もありません。ここにビューを作ります。",
        );

        // ---- mod.toml
        let mut provides = vec!["i18n".to_owned()];
        if self.has("widget") {
            provides.push(format!("widget:{id}"));
        }
        if self.has("peek") {
            provides.push(format!("peek:{id}"));
        }
        if self.has("panel") {
            provides.push(format!("panel:{id}"));
        }
        if self.has("desk") {
            provides.push(format!("desk:{id}"));
        }
        if self.has("tile") {
            provides.push("slot:quick.tiles".to_owned());
        }
        let mut m = format!(
            "id = {}\nname = {}\ndescription = {}\nversion = \"0.1.0\"\ntier = \"native\"\nkurashi = \">={}\"\n",
            toml_str(id),
            toml_str(&self.name),
            toml_str(&format!("{k}.description")),
            env!("CARGO_PKG_VERSION"),
        );
        m.push_str("# What it contributes (docs/MODS.md \"Integration contract\"; `kurashi mod points` lists every place).\n");
        m.push_str(&format!(
            "provides = [{}]\n",
            provides
                .iter()
                .map(|p| toml_str(p))
                .collect::<Vec<_>>()
                .join(", ")
        ));
        m.push_str("capabilities = []\ncost = \"low\"\n");
        m.push_str(&format!("icon = {}\n", toml_str(&self.icon)));
        if !self.uses.is_empty() {
            m.push_str("# What it reads and calls beyond its own (`?` = it works without).\n");
            m.push_str(&format!(
                "uses = [{}]\n",
                self.uses
                    .iter()
                    .map(|u| toml_str(u))
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
        if self.has("settings") {
            say("setting.show_name", "Show the name", "名前を表示");
            say(
                "setting.show_name.help",
                "Show the name next to the icon in the bar.",
                "バーのアイコンの横に名前を表示します。",
            );
            m.push_str(&format!(
                "\n[[setting]]\nkey = \"show_name\"\ntype = \"bool\"\ndefault = true\nlabel = {}\nhelp = {}\n",
                toml_str(&format!("{k}.setting.show_name")),
                toml_str(&format!("{k}.setting.show_name.help")),
            ));
        }
        let menu = self.has("menu") && self.has("panel");
        if menu {
            m.push_str(&format!(
                "\n# Its own menu (right-click on its module): the shell draws the rows.\n[[menu]]\nat = \"module\"\naction = \"mod.panel.open\"\nargs = {{ id = {}, panel = {} }}\nlabel = {}\nicon = {}\n",
                toml_str(id), toml_str(id), toml_str(&format!("{k}.open")), toml_str(&self.icon),
            ));
        }
        if self.has("widget") {
            // K72: a placeable module answers for every variant; these are starts to rewrite, not excuses to keep.
            let mut skips: Vec<(&str, &str)> = Vec::new();
            if !self.has("peek") {
                skips.push(("peek", "the glance says all there is so far"));
            }
            if !self.has("panel") {
                skips.push(("panel", "nothing more to show than the glance so far"));
            }
            if !self.has("desk") {
                skips.push(("desk", "nothing to show at rest so far"));
            }
            skips.push((
                "island-face",
                "no code of its own to raise a face (a host process or a crate would)",
            ));
            if !self.has("tile") {
                skips.push(("quick-tile", "nothing to switch"));
            }
            skips.push((
                "command",
                "no action of its own without code; its panel has its own `>` row",
            ));
            if !menu {
                skips.push(("menu", "nothing to offer without a panel to open"));
            }
            m.push_str("\n# K72: the variants it does not ship, and why (for the next reader, not the user).\n[skips]\n");
            for (key, why) in skips {
                m.push_str(&format!("{key} = {}\n", toml_str(why)));
            }
        }
        out.push(("mod.toml".into(), m));

        // ---- views
        let open = if self.has("panel") {
            format!("Store.act(\"mod.panel.open\", {{ id: \"{id}\", panel: \"{id}\" }})")
        } else {
            format!("Store.act(\"settings.open\", {{ page: \"mod:{id}\" }})")
        };
        let head = "import QtQuick\nimport qs.core\nimport qs.kit\n";
        let loader = "    // Handed in by the shell's loader.\n    required property var store\n    required property var theme\n    required property var i18n\n";
        if self.has("widget") {
            let name_bit = if self.has("settings") {
                format!(
                    "readonly property var cfg: (Store.docs[\"config\"] && Store.docs[\"config\"].values) || ({{}})\n    readonly property bool showName: cfg[\"mods.{id}.show_name\"] === undefined || cfg[\"mods.{id}.show_name\"].value === true"
                )
            } else {
                "readonly property bool showName: true".to_owned()
            };
            out.push(("qml/Widget.qml".into(), format!(
r#"{head}
// {name}'s glance: its icon, and its name beside it in a horizontal bar. A click (Return, Enter, Space) opens it.
// Everything it draws comes from the theme (no colour, size or duration of its own) and the kit (docs/MODS.md
// "Feeling native"); every string is in i18n/.
Item {{
    id: w
{loader}    // Set by the bar on a left or right edge: draw the vertical form, never rotated text.
    property bool vertical: false
    {name_bit}

    function open() {{ {open} }}

    implicitWidth: w.vertical ? Theme.barH : row.implicitWidth + Theme.gap * 2
    implicitHeight: w.vertical ? Theme.barH : Theme.controlH
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("{k}.open")
    Keys.onReturnPressed: w.open()
    Keys.onEnterPressed: w.open()
    Keys.onSpacePressed: w.open()

    Row {{
        id: row
        anchors.centerIn: parent
        spacing: Theme.xs
        Icon {{
            anchors.verticalCenter: parent.verticalCenter
            name: "{icon}"
        }}
        Label {{
            anchors.verticalCenter: parent.verticalCenter
            visible: w.showName && !w.vertical
            text: I18n.tr("{k}.name")
        }}
    }}

    FocusRing {{ anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }}
    MouseArea {{
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: w.open()
    }}
}}
"#, name = self.name, icon = self.icon)));
        }
        if self.has("peek") {
            out.push(("qml/Peek.qml".into(), format!(
r#"{head}
// {name}'s peek: the lines the Stage shows under the module on hover or focus (K35). A line is text; an empty list
// shows no card.
PeekLines {{
    id: peek
{loader}
    lines: [I18n.tr("{k}.name"), I18n.tr("{k}.hello")]
}}
"#, name = self.name)));
        }
        if self.has("panel") {
            out.push(("qml/Panel.qml".into(), format!(
r#"{head}
// {name}'s expanded view: a Stage card and a sidebar section. Draw every state the document can be in — empty,
// loading, an error with its reason, unavailable — not only the full one.
Item {{
    id: p
{loader}    // A host that offers a fixed height (a sidebar) sets it; the Stage card sets nothing.
    property real fillHeight: 0
    property int cardWidth: 360
    width: parent ? parent.width : cardWidth
    implicitHeight: body.implicitHeight + Theme.gap * 2

    Column {{
        id: body
        anchors {{ left: parent.left; right: parent.right; top: parent.top; margins: Theme.gap }}
        spacing: Theme.xs
        Row {{
            spacing: Theme.xs
            Icon {{ name: "{icon}" }}
            Label {{ text: I18n.tr("{k}.name"); font.weight: Theme.wBold }}
        }}
        Label {{
            width: parent.width
            wrapMode: Text.WordWrap
            dim: true
            text: I18n.tr("{k}.hello")
        }}
    }}
}}
"#, name = self.name, icon = self.icon)));
        }
        if self.has("desk") {
            out.push((format!("qml/desk/{id}.qml").into(), format!(
r#"{head}
// {name}'s desk card: a card on the desktop's widget column. It takes the column's width and sets its own height;
// with nothing to say it takes none (height 0).
Item {{
    id: dc
{loader}
    width: parent ? parent.width : 300
    implicitHeight: card.height

    Block {{
        id: card
        width: parent.width
        height: line.implicitHeight + Theme.gap * 2
        Row {{
            id: line
            anchors {{ left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.gap }}
            spacing: Theme.xs
            Icon {{ name: "{icon}" }}
            Label {{ text: I18n.tr("{k}.name") }}
        }}
    }}
}}
"#, name = self.name, icon = self.icon)));
        }
        if self.has("tile") {
            say("tile.idle", "Open", "開く");
            out.push(("qml/slots/quick.tiles.qml".into(), format!(
r#"{head}
// {name}'s quick tile: a one-step action (it opens the mod). A tile that switches something sets `toggles` and `on`,
// and says why it cannot (`reason`) or who holds it (`forcedBy`) instead of looking switchable.
QuickTile {{
    id: tile
{loader}
    label: I18n.tr("{k}.name")
    subtitle: I18n.tr("{k}.tile.idle")
    toggles: false
    acts: true
    hasPage: false
    onActivated: {open}
}}
"#, name = self.name)));
        }

        // ---- copy
        let table = |m: &BTreeMap<String, String>| {
            let mut t = format!(
                "# {} — the mod's strings (keys `{k}.*`). Every string a view shows is here.\n",
                self.name
            );
            for (key, text) in m {
                t.push_str(&format!(
                    "{} = {}\n",
                    toml_str(&format!("{k}.{key}")),
                    toml_str(text)
                ));
            }
            t
        };
        out.push(("i18n/en.toml".into(), table(&en)));
        out.push(("i18n/ja.toml".into(), table(&ja)));
        out.push(("README.md".into(), format!(
"# {name}\n\nA Kurashi mod, written by `kurashi mod new`. Check it with `kurashi mod check <this folder>` after every change.\n\n\
## What is here\n{parts}\n\
## What makes it native (docs/MODS.md \"Feeling native\")\n\
- [ ] Views import `qs.core` and `qs.kit` only; colours, sizes and motion come from `Theme`.\n\
- [ ] Every string is a key in `i18n/en.toml` and `i18n/ja.toml`.\n\
- [ ] Empty, loading, error and unavailable are drawn, not only the full state.\n\
- [ ] Every control is reachable by keyboard, shows the focus ring and has an accessible name.\n\
- [ ] Nothing runs while nothing is shown: no polling, a timer only while visible.\n\
- [ ] Each variant in `[skips]` has its real reason, or is built.\n\
- [ ] What it reads or calls beyond its own is in `uses`.\n\n\
## Going further\nAn action, a service or an island face of its own needs code. Today that is a crate in the shell's tree \
(docs/MODDING.md \"Routes\"); a program of the mod's own that the shell starts without such a crate, and Luau, are planned.\n",
            name = self.name,
            parts = out.iter().map(|(p, _)| format!("- `{}`\n", p.display())).collect::<String>(),
        )));
        Ok(out)
    }

    /// Writes the mod into `root/<id>`: built in a folder beside it, then renamed, so a failure leaves nothing half
    /// written. Refuses an id that is taken.
    pub fn write(&self, root: &Path) -> Result<PathBuf, ScaffoldError> {
        let files = self.files()?;
        let dir = root.join(&self.id);
        if dir.exists() {
            return Err(ScaffoldError::IdTaken);
        }
        let io = |e: std::io::Error| ScaffoldError::Write(e.to_string());
        std::fs::create_dir_all(root).map_err(io)?;
        let tmp = root.join(format!(".{}.new", self.id));
        let _ = std::fs::remove_dir_all(&tmp);
        let made = (|| -> std::io::Result<()> {
            for (rel, text) in &files {
                let p = tmp.join(rel);
                if let Some(parent) = p.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                std::fs::write(p, text)?;
            }
            std::fs::rename(&tmp, &dir)
        })();
        if let Err(e) = made {
            let _ = std::fs::remove_dir_all(&tmp);
            return Err(io(e));
        }
        Ok(dir)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::{self, Level};

    fn spec(with: &[&str]) -> Spec {
        Spec {
            id: "tea-timer".into(),
            name: "Tea \"timer\"".into(),
            icon: "emoji_food_beverage".into(),
            description: "A cup, on time.".into(),
            with: with.iter().map(|s| (*s).to_owned()).collect(),
            uses: vec!["doc:svc.clock".into()],
        }
    }

    /// The templates are the ruleset's example: whatever is ticked, what is written passes the check with no note.
    #[test]
    fn every_combination_of_parts_passes_the_check_as_written() {
        let v = semver::Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
        let all: Vec<&str> = PARTS.iter().map(|(n, _)| *n).collect();
        for mask in 1u32..(1 << all.len()) {
            let with: Vec<&str> = all
                .iter()
                .enumerate()
                .filter(|(i, _)| mask & (1 << i) != 0)
                .map(|(_, n)| *n)
                .collect();
            let s = spec(&with);
            if s.validate().is_err() {
                continue;
            }
            let tmp = tempfile::tempdir().unwrap();
            let dir = s.write(tmp.path()).unwrap();
            let r = check::check_dir(&dir, &v);
            // `uses` names a document the templates do not read yet: that one note is the author's to resolve.
            let notes: Vec<_> = r
                .findings
                .iter()
                .filter(|f| !(f.level == Level::Warn && f.rule == "use_unseen"))
                .collect();
            assert!(notes.is_empty(), "{with:?}\n{}", r.text());
        }
    }

    #[test]
    fn a_bad_spec_is_refused_and_a_taken_id_is_not_overwritten() {
        let mut s = spec(&["widget"]);
        s.id = "Tea".into();
        assert_eq!(s.files().unwrap_err(), ScaffoldError::IdInvalid);
        s.id = "loaded".into();
        assert_eq!(s.files().unwrap_err(), ScaffoldError::IdInvalid);
        let mut s = spec(&["peek", "menu"]);
        assert_eq!(s.files().unwrap_err(), ScaffoldError::NothingChosen);
        s.with = vec!["widget".into(), "gauge".into()];
        assert_eq!(
            s.files().unwrap_err(),
            ScaffoldError::PartUnknown("gauge".into())
        );
        let s = spec(&["widget", "panel"]);
        let tmp = tempfile::tempdir().unwrap();
        let dir = s.write(tmp.path()).unwrap();
        assert!(dir.join("qml/Panel.qml").is_file());
        assert_eq!(s.write(tmp.path()).unwrap_err(), ScaffoldError::IdTaken);
        assert!(!tmp.path().join(".tea-timer.new").exists());
    }
}
