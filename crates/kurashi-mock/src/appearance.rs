//! Styles, looks and palettes as the daemon serves them (K53, W29): `theme.appearance`, the document
//! `theme.previews`, and the actions `theme.style.apply {name}` / `theme.look.apply {name}`, answered in memory
//! against the mock's `config` document, so Settings' Appearance page can be prototyped against the mock.
//! The packs and their preview tokens come from `kurashi-theme` itself (the same files the daemon reads); the mock
//! has no config layers, so a pack's values are written into `config` with the source the daemon names
//! (`theme` / `style:<name>`, `look:<name>`) and a reset puts the schema default back.

use kurashi_theme::FontProvider;
use kurashi_theme::appearance::{Kind, LOOK_KEYS, STYLE_KEYS, all, find};
use serde_json::{Map, Value, json};

use crate::state::Fail;

/// The daemon's refusal of an action without a name.
pub const ERR_NAME: &str = "config.error.appearance_name";
/// A name that is no pack (the config's own code for a value outside the offers).
pub const ERR_UNKNOWN: &str = "config.error.enum";

/// The mock claims every font: a preview names the first family of its chain.
struct AnyFont;
impl FontProvider for AnyFont {
    fn is_installed(&self, _family: &str) -> bool {
        true
    }
}

pub fn handles(action: &str) -> bool {
    matches!(action, "theme.style.apply" | "theme.look.apply")
}

fn text(config: &Value, key: &str) -> String {
    config["values"][key]["value"]
        .as_str()
        .unwrap_or_default()
        .to_owned()
}

fn source(config: &Value, key: &str) -> String {
    config["values"][key]["source"]["kind"]
        .as_str()
        .unwrap_or_default()
        .to_owned()
}

/// `theme.previews`: every style whole, every look in `palette`/`scheme`, every bundled palette in `look`/`scheme`.
pub fn previews(palette: &str, look: &str, scheme: &str) -> Value {
    let fonts = AnyFont;
    let palette = if kurashi_theme::bundled_names().contains(&palette) {
        palette
    } else {
        "wa-iro"
    };
    json!({
        "styles": all(Kind::Style).iter()
            .filter_map(|p| kurashi_theme::style_preview(&p.name, &fonts)).collect::<Vec<_>>(),
        "looks": all(Kind::Look).iter()
            .filter_map(|p| kurashi_theme::look_preview(&p.name, palette, scheme, &fonts)).collect::<Vec<_>>(),
        "palettes": kurashi_theme::bundled_names().iter()
            .filter_map(|n| kurashi_theme::palette_preview(n, look, scheme, &fonts)).collect::<Vec<_>>(),
    })
}

/// The pack values of the style and look in effect, as `config` entries with the theme source, over `config`'s
/// non-user values (a user value stays: it sits above the theme layer). Returns the patch of `values`.
fn settle(config: &Value, defaults: &Map<String, Value>) -> Map<String, Value> {
    let style_name = text(config, "theme.style");
    let style = find(Kind::Style, &style_name);
    let look_name = if source(config, "theme.look") == "user" {
        text(config, "theme.look")
    } else {
        style
            .as_ref()
            .map(|s| s.look.clone())
            .unwrap_or_else(|| text(config, "theme.look"))
    };
    let look = find(Kind::Look, &look_name);
    let mut ops = Map::new();
    // Every appearance key not set by the user goes back to its default first, then the packs write theirs.
    for key in STYLE_KEYS.iter().chain(["theme.colors.scheme"].iter()) {
        if source(config, key) != "user"
            && let Some(d) = defaults.get(*key)
        {
            ops.insert((*key).into(), d.clone());
        }
    }
    for (key, value, from) in kurashi_theme::appearance::layer(style.as_ref(), look.as_ref()) {
        if source(config, &key) != "user" {
            ops.insert(
                key,
                json!({"value": value, "source": {"kind": "theme", "name": from}}),
            );
        }
    }
    ops
}

/// `theme.appearance` for `config` (after `settle`): the packs in effect and the style keys the user set.
pub fn summary(config: &Value) -> Value {
    let overrides: Vec<&str> = STYLE_KEYS
        .iter()
        .copied()
        .filter(|k| matches!(source(config, k).as_str(), "user" | "profile"))
        .collect();
    json!({
        "style": text(config, "theme.style"),
        "look": text(config, "theme.look"),
        "palette": text(config, "theme.colors.palette"),
        "scheme": text(config, "theme.colors.scheme"),
        "overrides": overrides,
    })
}

/// The config document with the packs of its style settled in (the mock's start).
pub fn initial(config: Value) -> Value {
    let defaults = config["values"].as_object().cloned().unwrap_or_default();
    let mut next = config;
    let ops = settle(&next, &defaults);
    for (k, v) in ops {
        next["values"][&k] = v;
    }
    next
}

/// What an action changes: the `config` values patch and the new config (for the theme and previews).
pub struct Outcome {
    pub values: Map<String, Value>,
    pub config: Value,
}

/// `theme.style.apply {name}` / `theme.look.apply {name}`: the user's values of the kind's keys are reset (the
/// daemon's one undoable change), the pick is set as the user's, and the packs settle again.
pub fn act(
    config: &Value,
    defaults: &Map<String, Value>,
    action: &str,
    args: &Value,
) -> Result<Outcome, Fail> {
    let name = args["name"]
        .as_str()
        .filter(|n| !n.is_empty())
        .ok_or_else(|| Fail::invalid(ERR_NAME))?;
    let (kind, keys, key) = match action {
        "theme.style.apply" => (Kind::Style, STYLE_KEYS, "theme.style"),
        _ => (Kind::Look, LOOK_KEYS, "theme.look"),
    };
    if !(kind == Kind::Style && name == "none") && find(kind, name).is_none() {
        return Err(Fail::invalid(ERR_UNKNOWN));
    }
    let mut next = config.clone();
    let mut values = Map::new();
    for k in keys.iter().filter(|k| **k != key) {
        if source(config, k) == "user" {
            let d = defaults.get(*k).cloned().unwrap_or(Value::Null);
            next["values"][*k] = d.clone();
            values.insert((*k).into(), d);
        }
    }
    let pick = json!({"value": name, "source": {"kind": "user"}});
    next["values"][key] = pick.clone();
    values.insert(key.into(), pick);
    for (k, v) in settle(&next, defaults) {
        next["values"][&k] = v.clone();
        values.insert(k, v);
    }
    Ok(Outcome {
        values,
        config: next,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> (Value, Map<String, Value>) {
        let c = crate::documents::config(kurashi_schema::v1::registry());
        let d = c["values"].as_object().cloned().unwrap();
        (initial(c), d)
    }

    #[test]
    fn washi_is_settled_at_start_with_the_style_as_source() {
        let (c, _) = config();
        let a = summary(&c);
        assert_eq!(a["style"], "washi");
        assert_eq!(a["look"], "washi");
        assert_eq!(a["palette"], "wa-iro");
        assert_eq!(a["overrides"], json!([]));
        assert_eq!(
            c["values"]["theme.colors.palette"]["source"],
            json!({"kind": "theme", "name": "style:washi"})
        );
        let p = previews("wa-iro", "washi", "light");
        let washi = p["looks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|l| l["name"] == "washi")
            .unwrap();
        assert_eq!(washi["frame"], "paper");
        assert!(p["styles"].as_array().unwrap().len() > 10);
    }

    #[test]
    fn a_style_resets_the_users_appearance_and_a_look_keeps_the_palette() {
        let (mut c, d) = config();
        c["values"]["theme.chrome"] = json!({"value": "keycap", "source": {"kind": "user"}});
        assert_eq!(summary(&c)["overrides"], json!(["theme.chrome"]));
        let out = act(&c, &d, "theme.style.apply", &json!({"name": "win95"})).unwrap();
        let a = summary(&out.config);
        assert_eq!(a["style"], "win95");
        assert_eq!(a["palette"], "win95");
        assert_eq!(a["overrides"], json!([]));
        assert_ne!(
            out.config["values"]["theme.chrome"]["source"]["kind"],
            "user"
        );

        let out = act(
            &out.config,
            &d,
            "theme.look.apply",
            &json!({"name": "sekai"}),
        )
        .unwrap();
        let a = summary(&out.config);
        assert_eq!(a["look"], "sekai");
        assert_eq!(a["palette"], "win95", "the style's palette stays");
        assert_eq!(a["overrides"], json!(["theme.look"]));

        assert_eq!(
            act(&c, &d, "theme.style.apply", &json!({}))
                .err()
                .unwrap()
                .msg,
            ERR_NAME
        );
        assert_eq!(
            act(&c, &d, "theme.look.apply", &json!({"name": "nope"}))
                .err()
                .unwrap()
                .msg,
            ERR_UNKNOWN
        );
    }
}
