//! The two backends (K26, docs/ux/wallpaper.md): awww (default) and swww. The adapter is the only
//! place that knows their flags and output formats; the rest of the mod speaks [`BackendId`],
//! [`ImgOpts`] and [`Output`].
//!
//! awww 0.12.1 (its man page, `awww query --json`): `{"<namespace>": [{"name", "width", "height",
//! "scale", "displaying": {"image": "<path>" | "color": "<hex>"}}]}`. swww has no JSON query in the
//! docs this was written against; its text form `OUTPUT: WxH, scale: N, currently displaying: image:
//! PATH` is parsed as documented, and is not verified against a running swww (see the report).

use std::collections::BTreeMap;

use serde_json::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackendId {
    Awww,
    Swww,
}

/// Every backend the mod knows, in the order its choice source offers them.
pub const BACKENDS: [BackendId; 2] = [BackendId::Awww, BackendId::Swww];

impl BackendId {
    pub fn parse(s: &str) -> Option<Self> {
        BACKENDS.into_iter().find(|b| b.id() == s)
    }

    pub fn id(self) -> &'static str {
        match self {
            Self::Awww => "awww",
            Self::Swww => "swww",
        }
    }

    /// The client command (`awww img …`).
    pub fn cli(self) -> &'static str {
        self.id()
    }

    /// The daemon the client talks to.
    pub fn daemon(self) -> &'static str {
        match self {
            Self::Awww => "awww-daemon",
            Self::Swww => "swww-daemon",
        }
    }

    /// Flags of the daemon start. `--no-cache` (awww): the daemon does not restore its own last
    /// image, because the mod is the one restore owner (its state file is the truth).
    pub fn daemon_args(self) -> Vec<String> {
        match self {
            Self::Awww => vec!["--no-cache".into()],
            Self::Swww => Vec::new(),
        }
    }

    pub fn query_args(self) -> Vec<String> {
        match self {
            Self::Awww => vec!["query".into(), "--json".into()],
            Self::Swww => vec!["query".into()],
        }
    }

    /// `img <path> [--outputs a,b] --resize … --transition-type …`. Every flag is passed: the
    /// backends read their `*_TRANSITION*` environment only when a flag is absent.
    pub fn img_args(self, path: &str, opts: &ImgOpts<'_>) -> Vec<String> {
        let mut args = vec!["img".to_string(), path.to_string()];
        if !opts.outputs.is_empty() {
            args.push("--outputs".into());
            args.push(opts.outputs.join(","));
        }
        args.extend(["--resize".into(), opts.fit.to_string()]);
        // Only awww has a crop anchor; swww crops around the centre.
        if self == Self::Awww && opts.fit == "crop" {
            args.extend(["--crop-gravity".into(), opts.crop_anchor.to_string()]);
        }
        args.extend([
            "--transition-type".into(),
            opts.transition.to_string(),
            "--transition-duration".into(),
            format!("{:.2}", opts.duration),
            "--transition-angle".into(),
            opts.angle.to_string(),
        ]);
        args
    }

    /// The outputs a query prints. An error is the parser's reason, shown as text.
    pub fn parse_query(self, stdout: &str) -> Result<Vec<Output>, String> {
        match self {
            Self::Awww => parse_awww_json(stdout),
            Self::Swww => Ok(parse_text(stdout)),
        }
    }
}

/// What `img` is given: the target outputs (empty = every output), the Settings in effect.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ImgOpts<'a> {
    pub outputs: &'a [String],
    pub fit: &'a str,
    pub crop_anchor: &'a str,
    pub transition: &'a str,
    pub duration: f64,
    pub angle: i64,
}

/// An output the backend drives, as its query reports it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Output {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub scale: u32,
    /// The image the backend shows on it now, when it reports one.
    pub shows: Option<String>,
}

/// `awww 0.12.1` → `0.12.1`: the last word of the first line that has one.
pub fn parse_version(stdout: &str) -> Option<String> {
    stdout
        .lines()
        .find(|l| !l.trim().is_empty())
        .and_then(|l| l.split_whitespace().last())
        .map(str::to_string)
}

fn parse_awww_json(stdout: &str) -> Result<Vec<Output>, String> {
    let v: Value = serde_json::from_str(stdout).map_err(|e| e.to_string())?;
    let namespaces = v
        .as_object()
        .ok_or_else(|| "query: expected an object".to_string())?;
    let mut outputs: BTreeMap<String, Output> = BTreeMap::new();
    for list in namespaces.values() {
        for o in list.as_array().into_iter().flatten() {
            let Some(name) = o["name"].as_str() else {
                continue;
            };
            outputs.insert(
                name.to_string(),
                Output {
                    name: name.to_string(),
                    width: u32_of(&o["width"]),
                    height: u32_of(&o["height"]),
                    scale: u32_of(&o["scale"]).max(1),
                    shows: o["displaying"]["image"].as_str().map(str::to_string),
                },
            );
        }
    }
    Ok(outputs.into_values().collect())
}

fn u32_of(v: &Value) -> u32 {
    v.as_u64().and_then(|n| u32::try_from(n).ok()).unwrap_or(0)
}

/// `OUTPUT: 2560x1440, scale: 1, currently displaying: image: /path` per line; lines it does not
/// understand are skipped (a header, a message).
fn parse_text(stdout: &str) -> Vec<Output> {
    let mut out = BTreeMap::new();
    for line in stdout.lines() {
        let Some((name, rest)) = line.split_once(": ") else {
            continue;
        };
        let name = name.trim();
        let Some((w, h)) = rest
            .split(',')
            .next()
            .and_then(|size| size.trim().split_once('x'))
            .and_then(|(w, h)| Some((w.parse::<u32>().ok()?, h.parse::<u32>().ok()?)))
        else {
            continue;
        };
        let scale = rest
            .split(',')
            .find_map(|part| part.trim().strip_prefix("scale: "))
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(1)
            .max(1);
        let shows = rest
            .split_once("image: ")
            .map(|(_, path)| path.trim().to_string());
        out.insert(
            name.to_string(),
            Output {
                name: name.to_string(),
                width: w,
                height: h,
                scale,
                shows,
            },
        );
    }
    out.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(outputs: &[String]) -> ImgOpts<'_> {
        ImgOpts {
            outputs,
            fit: "crop",
            crop_anchor: "center",
            transition: "fade",
            duration: 1.0,
            angle: 45,
        }
    }

    #[test]
    fn awww_img_takes_the_flags_the_card_names() {
        let outputs = vec!["DP-1".to_string()];
        let args = BackendId::Awww.img_args("/p/a.png", &opts(&outputs));
        assert_eq!(
            args.join(" "),
            "img /p/a.png --outputs DP-1 --resize crop --crop-gravity center \
             --transition-type fade --transition-duration 1.00 --transition-angle 45"
        );
    }

    #[test]
    fn no_outputs_means_every_output_and_swww_has_no_crop_anchor() {
        let args = BackendId::Swww.img_args("/p/a.png", &opts(&[]));
        assert!(!args.iter().any(|a| a == "--outputs" || a == "--crop-gravity"));
        assert_eq!(args[0..2], ["img", "/p/a.png"]);
    }

    #[test]
    fn a_fit_other_than_crop_drops_the_anchor() {
        let mut o = opts(&[]);
        o.fit = "no";
        let args = BackendId::Awww.img_args("/p/a.png", &o);
        assert!(!args.iter().any(|a| a == "--crop-gravity"));
        assert!(args.windows(2).any(|w| w == ["--resize", "no"]));
    }

    #[test]
    fn awww_query_json_lists_each_output_under_its_namespace() {
        let json = r#"{"": [
            {"name": "DP-2", "width": 1920, "height": 1080, "scale": 1,
             "displaying": {"color": "000000"}},
            {"name": "DP-1", "width": 2560, "height": 1440, "scale": 2,
             "displaying": {"image": "/w/a.png"}}
        ]}"#;
        let outputs = BackendId::Awww.parse_query(json).unwrap();
        let names: Vec<_> = outputs.iter().map(|o| o.name.as_str()).collect();
        assert_eq!(names, ["DP-1", "DP-2"], "sorted by name");
        assert_eq!(outputs[0].shows.as_deref(), Some("/w/a.png"));
        assert_eq!((outputs[0].width, outputs[0].scale), (2560, 2));
        assert_eq!(outputs[1].shows, None, "a colour is not an image");
    }

    #[test]
    fn a_query_that_is_not_json_is_an_error_not_an_empty_list() {
        assert!(BackendId::Awww.parse_query("Failed to connect").is_err());
    }

    #[test]
    fn swww_text_query_is_parsed_per_documented_line() {
        let text = "HDMI-A-1: 1920x1080, scale: 1, currently displaying: image: /w/b.jpg\n\
                    garbage line\n\
                    DP-1: 2560x1440, scale: 1, currently displaying: color: 000000\n";
        let outputs = BackendId::Swww.parse_query(text).unwrap();
        assert_eq!(outputs.len(), 2);
        assert_eq!(outputs[0].name, "DP-1");
        assert_eq!(outputs[0].shows, None);
        assert_eq!(outputs[1].shows.as_deref(), Some("/w/b.jpg"));
    }

    #[test]
    fn version_is_the_last_word_of_the_first_line() {
        assert_eq!(parse_version("awww 0.12.1\n").as_deref(), Some("0.12.1"));
        assert_eq!(parse_version("\n  \n"), None);
    }

    #[test]
    fn backend_ids_are_the_two_known_names() {
        assert_eq!(BackendId::parse("awww"), Some(BackendId::Awww));
        assert_eq!(BackendId::parse("swww"), Some(BackendId::Swww));
        assert_eq!(BackendId::parse("hyprpaper"), None);
        assert_eq!(BackendId::Awww.daemon_args(), ["--no-cache"]);
    }
}
