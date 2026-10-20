//! Wallhaven in the picker (K48 (3); docs/ux/wallpaper.md "Wallhaven"; shellseikatsu `Services/WallhavenService.qml`).
//! Two actions, both on request only (Ma: nothing is fetched while the picker's Wallhaven tab is closed):
//!
//! - `wallpaper.wallhaven.search {query?, categories?, purity?, sorting?, page?, seed?}` asks the search API for one
//!   page and fetches that page's small thumbnails into the cache, so the picker shows local files. SFW only unless
//!   asked; NSFW needs the API key (`wallhaven_api_key`, sent as the `X-API-Key` header, never in a URL).
//! - `wallpaper.wallhaven.download {id}` fetches one picture into the mod's data folder
//!   (`$XDG_DATA_HOME/kurashi/wallpaper/wallhaven/wallhaven-<id>.<ext>`) and answers its path; the picker then sets it
//!   with `wallpaper.set` like any library picture.
//!
//! Refusals are keys: Wallhaven off in the settings, offline, a bad key, rate limited, a reply we cannot read.

use std::path::{Path, PathBuf};
use std::time::Duration;

use kurashi_mod_api::{ActionError, Settings};
use serde_json::{Value, json};

use crate::Dirs;

pub const BASE_DEFAULT: &str = "https://wallhaven.cc";
/// Sortings the API takes.
pub const SORTINGS: &[&str] = &[
    "toplist",
    "date_added",
    "relevance",
    "random",
    "views",
    "favorites",
];
const QUERY_MAX: usize = 200;
const THUMB_MAX_BYTES: u64 = 2 * 1024 * 1024;
const FULL_MAX_BYTES: u64 = 80 * 1024 * 1024;
/// Thumbnails kept; the oldest half goes when there are more.
const THUMBS_KEEP: usize = 600;
/// Thumbnails fetched at once.
const PARALLEL: usize = 6;

pub const ERR_OFF: &str = "mod-wallpaper.wallhaven.error.off";
pub const ERR_OFFLINE: &str = "mod-wallpaper.wallhaven.error.offline";
pub const ERR_KEY: &str = "mod-wallpaper.wallhaven.error.bad_key";
pub const ERR_RATE: &str = "mod-wallpaper.wallhaven.error.rate_limited";
pub const ERR_REPLY: &str = "mod-wallpaper.wallhaven.error.bad_reply";
pub const ERR_FAILED: &str = "mod-wallpaper.wallhaven.error.failed";
pub const ERR_ARGS: &str = "mod-wallpaper.wallhaven.error.args";
pub const ERR_NSFW_KEY: &str = "mod-wallpaper.wallhaven.error.nsfw_key";
pub const ERR_NOT_FOUND: &str = "mod-wallpaper.wallhaven.error.not_found";

/// `KURASHI_WALLHAVEN_API` (tests and the sandbox point it at a fixture server), else wallhaven.cc.
pub fn base_from_env() -> String {
    std::env::var("KURASHI_WALLHAVEN_API")
        .ok()
        .filter(|v| !v.is_empty())
        .map(|v| v.trim_end_matches('/').to_owned())
        .unwrap_or_else(|| BASE_DEFAULT.into())
}

/// The settings Wallhaven reads: on/off and the optional API key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WhConfig {
    pub on: bool,
    pub key: Option<String>,
}

impl WhConfig {
    pub fn read(settings: &Settings) -> Self {
        Self {
            on: settings
                .get("wallhaven")
                .and_then(|v| v.as_bool())
                .unwrap_or(true),
            key: settings
                .get("wallhaven_api_key")
                .and_then(|v| v.as_str().map(str::trim).map(str::to_owned))
                .filter(|k| !k.is_empty()),
        }
    }
}

/// One search, checked.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Query {
    pub q: String,
    pub categories: String,
    pub purity: String,
    pub sorting: String,
    pub page: u32,
    pub seed: Option<String>,
}

/// Three `0`/`1` flags, not all `0`.
fn flags(s: &str) -> bool {
    s.len() == 3 && s.bytes().all(|b| b == b'0' || b == b'1') && s != "000"
}

/// The search arguments: defaults for what is left out, refusals for what is wrong. SFW (`100`) unless asked; the
/// NSFW flag (the third) only with an API key.
pub fn parse_query(args: &Value, has_key: bool) -> Result<Query, ActionError> {
    let bad = || ActionError::Invalid(ERR_ARGS.into());
    let text = |k: &str, d: &str| -> Result<String, ActionError> {
        match args.get(k) {
            None | Some(Value::Null) => Ok(d.to_owned()),
            Some(Value::String(s)) => Ok(s.trim().to_owned()),
            Some(_) => Err(bad()),
        }
    };
    let q = text("query", "")?;
    if q.chars().count() > QUERY_MAX {
        return Err(bad());
    }
    let categories = text("categories", "111")?;
    let purity = text("purity", "100")?;
    let sorting = text("sorting", "toplist")?;
    if !flags(&categories) || !flags(&purity) || !SORTINGS.contains(&sorting.as_str()) {
        return Err(bad());
    }
    if purity.ends_with('1') && !has_key {
        return Err(ActionError::Invalid(ERR_NSFW_KEY.into()));
    }
    let page = match args.get("page") {
        None | Some(Value::Null) => 1,
        Some(v) => v
            .as_u64()
            .and_then(|p| u32::try_from(p).ok())
            .filter(|p| (1..=10_000).contains(p))
            .ok_or_else(bad)?,
    };
    let seed = match args.get("seed") {
        None | Some(Value::Null) => None,
        Some(Value::String(s))
            if !s.is_empty() && s.len() <= 16 && s.bytes().all(|b| b.is_ascii_alphanumeric()) =>
        {
            Some(s.clone())
        }
        Some(_) => return Err(bad()),
    };
    Ok(Query {
        q,
        categories,
        purity,
        sorting,
        page,
        seed,
    })
}

/// Percent-encodes a query value (RFC 3986 unreserved characters stay).
pub fn encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(char::from(b));
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub fn search_url(base: &str, q: &Query) -> String {
    let mut url = format!(
        "{base}/api/v1/search?categories={}&purity={}&sorting={}&page={}",
        q.categories, q.purity, q.sorting, q.page
    );
    if q.sorting == "toplist" {
        url.push_str("&topRange=1M");
    }
    if !q.q.is_empty() {
        url.push_str("&q=");
        url.push_str(&encode(&q.q));
    }
    if let Some(seed) = &q.seed {
        url.push_str("&seed=");
        url.push_str(seed);
    }
    url
}

/// A Wallhaven id: short, lowercase letters and digits.
pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 16
        && id
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
}

/// One picture of a reply.
#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub id: String,
    pub thumb_url: String,
    pub full_url: String,
    pub page_url: String,
    pub resolution: String,
    pub file_size: u64,
    pub file_type: String,
    pub purity: String,
    pub category: String,
    pub colors: Vec<String>,
}

/// One page of a search.
#[derive(Clone, Debug, PartialEq)]
pub struct Page {
    pub hits: Vec<Hit>,
    pub page: u64,
    pub last_page: u64,
    pub total: u64,
    pub seed: Option<String>,
}

fn hit_of(v: &Value) -> Option<Hit> {
    let s = |k: &str| v[k].as_str().unwrap_or("").to_owned();
    let id = s("id");
    let full_url = s("path");
    if !valid_id(&id) || full_url.is_empty() {
        return None;
    }
    let thumbs = &v["thumbs"];
    let thumb_url = thumbs["small"]
        .as_str()
        .or_else(|| thumbs["large"].as_str())
        .or_else(|| thumbs["original"].as_str())
        .unwrap_or("")
        .to_owned();
    Some(Hit {
        id,
        thumb_url,
        full_url,
        page_url: s("url"),
        resolution: s("resolution"),
        file_size: v["file_size"].as_u64().unwrap_or(0),
        file_type: s("file_type"),
        purity: s("purity"),
        category: s("category"),
        colors: v["colors"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|c| c.as_str())
            .filter(|c| c.len() == 7 && c.starts_with('#'))
            .map(str::to_owned)
            .collect(),
    })
}

/// A search reply. `{"error": …}` and anything without `data` is an error key.
pub fn parse_search(body: &str) -> Result<Page, &'static str> {
    let v: Value = serde_json::from_str(body).map_err(|_| ERR_REPLY)?;
    if v.get("error").is_some() {
        return Err(ERR_FAILED);
    }
    let data = v["data"].as_array().ok_or(ERR_REPLY)?;
    let meta = &v["meta"];
    Ok(Page {
        hits: data.iter().filter_map(hit_of).collect(),
        page: meta["current_page"].as_u64().unwrap_or(1),
        last_page: meta["last_page"].as_u64().unwrap_or(1).max(1),
        total: meta["total"].as_u64().unwrap_or(data.len() as u64),
        seed: meta["seed"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(str::to_owned),
    })
}

/// A wallpaper info reply (`/api/v1/w/<id>`).
pub fn parse_info(body: &str) -> Result<Hit, &'static str> {
    let v: Value = serde_json::from_str(body).map_err(|_| ERR_REPLY)?;
    if v.get("error").is_some() {
        return Err(ERR_NOT_FOUND);
    }
    hit_of(&v["data"]).ok_or(ERR_REPLY)
}

/// The file extension of a URL's last segment (`jpg`, `png`, `webp`), else `jpg`.
pub fn ext_of(url: &str) -> &str {
    let last = url.rsplit('/').next().unwrap_or("");
    let last = last.split(['?', '#']).next().unwrap_or("");
    match last.rsplit_once('.') {
        Some((_, e)) if matches!(e, "jpg" | "jpeg" | "png" | "webp" | "gif") => e,
        _ => "jpg",
    }
}

/// The picture of `id` in `dir`, if it was downloaded.
pub fn downloaded(dir: &Path, id: &str) -> Option<PathBuf> {
    ["jpg", "jpeg", "png", "webp", "gif"]
        .iter()
        .map(|e| dir.join(format!("wallhaven-{id}.{e}")))
        .find(|p| p.is_file())
}

impl Dirs {
    /// Where Wallhaven pictures are saved: the mod's data folder.
    pub fn wallhaven(&self) -> PathBuf {
        self.data.join("wallpaper").join("wallhaven")
    }
    /// The search thumbnails.
    pub fn wallhaven_thumbs(&self) -> PathBuf {
        self.cache.join("wallpaper").join("wallhaven")
    }
}

#[derive(Debug)]
enum Fetch {
    Offline,
    Status(u16),
    Body,
}

fn key_of(e: &Fetch) -> &'static str {
    match e {
        Fetch::Offline => ERR_OFFLINE,
        Fetch::Status(401 | 403) => ERR_KEY,
        Fetch::Status(404) => ERR_NOT_FOUND,
        Fetch::Status(429) => ERR_RATE,
        Fetch::Status(_) => ERR_FAILED,
        Fetch::Body => ERR_REPLY,
    }
}

/// A GET with the API key header when there is one; at most `max` bytes.
fn get(url: &str, key: Option<&str>, max: u64, timeout: Duration) -> Result<Vec<u8>, Fetch> {
    use std::io::Read;
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .user_agent(concat!(
            "kurashi-mod-wallpaper/",
            env!("CARGO_PKG_VERSION"),
            " (kurashi-shell)"
        ))
        .build();
    let agent = ureq::Agent::new_with_config(config);
    let mut req = agent.get(url);
    if let Some(k) = key {
        req = req.header("X-API-Key", k);
    }
    let mut response = match req.call() {
        Ok(r) => r,
        Err(ureq::Error::StatusCode(code)) => return Err(Fetch::Status(code)),
        Err(e) => {
            tracing::debug!(error = %e, "wallhaven: no answer");
            return Err(Fetch::Offline);
        }
    };
    let mut body = Vec::new();
    response
        .body_mut()
        .as_reader()
        .take(max)
        .read_to_end(&mut body)
        .map_err(|_| Fetch::Body)?;
    Ok(body)
}

/// `wallpaper.wallhaven.search`: one page, its thumbnails in the cache.
pub async fn search(
    settings: &Settings,
    dirs: &Dirs,
    base: &str,
    args: Value,
) -> Result<Option<Value>, ActionError> {
    let cfg = WhConfig::read(settings);
    if !cfg.on {
        return Err(ActionError::Unavailable(ERR_OFF.into()));
    }
    let q = parse_query(&args, cfg.key.is_some())?;
    let url = search_url(base, &q);
    let (thumbs, saved) = (dirs.wallhaven_thumbs(), dirs.wallhaven());
    let reply = tokio::task::spawn_blocking(move || {
        let body = get(&url, cfg.key.as_deref(), 4 * 1024 * 1024, Duration::from_secs(15))
            .map_err(|e| key_of(&e))?;
        let page = parse_search(&String::from_utf8_lossy(&body))?;
        let made = fetch_thumbs(&thumbs, &page.hits);
        Ok::<_, &'static str>(reply_of(&page, &made, &saved))
    })
    .await
    .map_err(|e| ActionError::Internal(e.to_string()))?;
    reply
        .map(Some)
        .map_err(|k| ActionError::Unavailable(k.into()))
}

/// The thumbnails of `hits` in `dir`, fetched when missing, [`PARALLEL`] at a time: per hit its file or `None`.
fn fetch_thumbs(dir: &Path, hits: &[Hit]) -> Vec<Option<PathBuf>> {
    let _ = std::fs::create_dir_all(dir);
    let mut out = vec![None; hits.len()];
    for (chunk_i, chunk) in hits.chunks(PARALLEL).enumerate() {
        std::thread::scope(|s| {
            let handles: Vec<_> = chunk
                .iter()
                .map(|h| {
                    s.spawn(move || {
                        if h.thumb_url.is_empty() {
                            return None;
                        }
                        let file = dir.join(format!("{}.{}", h.id, ext_of(&h.thumb_url)));
                        if file.is_file() {
                            return Some(file);
                        }
                        let body =
                            get(&h.thumb_url, None, THUMB_MAX_BYTES, Duration::from_secs(10)).ok()?;
                        let part = file.with_extension("part");
                        std::fs::write(&part, body).ok()?;
                        std::fs::rename(&part, &file).ok()?;
                        Some(file)
                    })
                })
                .collect();
            for (j, h) in handles.into_iter().enumerate() {
                out[chunk_i * PARALLEL + j] = h.join().ok().flatten();
            }
        });
    }
    trim(dir, THUMBS_KEEP);
    out
}

/// The reply of a search: the page, each picture with its local thumbnail (or why it has none) and, when it was
/// downloaded before, its saved file.
pub fn reply_of(page: &Page, thumbs: &[Option<PathBuf>], saved: &Path) -> Value {
    let rows: Vec<Value> = page
        .hits
        .iter()
        .zip(thumbs.iter().chain(std::iter::repeat(&None)))
        .map(|(h, t)| {
            let mut row = json!({
                "id": h.id,
                "resolution": h.resolution,
                "file_size": h.file_size,
                "file_type": h.file_type,
                "purity": h.purity,
                "category": h.category,
                "colors": h.colors,
                "url": h.page_url,
            });
            match t {
                Some(p) => row["thumb"] = json!(p.display().to_string()),
                None => row["thumb_error"] = json!("mod-wallpaper.wallhaven.error.thumb"),
            }
            if let Some(p) = downloaded(saved, &h.id) {
                row["local"] = json!(p.display().to_string());
            }
            row
        })
        .collect();
    let mut v = json!({
        "rows": rows,
        "page": page.page,
        "last_page": page.last_page,
        "total": page.total,
    });
    if let Some(seed) = &page.seed {
        v["seed"] = json!(seed);
    }
    v
}

/// `wallpaper.wallhaven.download {id}`: the picture in the data folder (fetched once), as `{path}`.
pub async fn download(
    settings: &Settings,
    dirs: &Dirs,
    base: &str,
    args: Value,
) -> Result<Option<Value>, ActionError> {
    let cfg = WhConfig::read(settings);
    if !cfg.on {
        return Err(ActionError::Unavailable(ERR_OFF.into()));
    }
    let id = args["id"]
        .as_str()
        .filter(|id| valid_id(id))
        .ok_or_else(|| ActionError::Invalid(ERR_ARGS.into()))?
        .to_owned();
    let dir = dirs.wallhaven();
    if let Some(p) = downloaded(&dir, &id) {
        return Ok(Some(json!({"path": p.display().to_string(), "fetched": false})));
    }
    let info_url = format!("{base}/api/v1/w/{id}");
    let got = tokio::task::spawn_blocking(move || {
        let body = get(&info_url, cfg.key.as_deref(), 1024 * 1024, Duration::from_secs(15))
            .map_err(|e| key_of(&e))?;
        let hit = parse_info(&String::from_utf8_lossy(&body))?;
        let bytes = get(&hit.full_url, cfg.key.as_deref(), FULL_MAX_BYTES, Duration::from_secs(90))
            .map_err(|e| key_of(&e))?;
        // A picture must decode: an HTML error page saved as .jpg would be set as a broken wallpaper.
        if image::guess_format(&bytes).is_err() {
            return Err(ERR_REPLY);
        }
        std::fs::create_dir_all(&dir).map_err(|_| ERR_FAILED)?;
        let file = dir.join(format!("wallhaven-{id}.{}", ext_of(&hit.full_url)));
        let part = dir.join(format!(".wallhaven-{id}.part"));
        std::fs::write(&part, bytes).map_err(|_| ERR_FAILED)?;
        std::fs::rename(&part, &file).map_err(|_| ERR_FAILED)?;
        Ok::<_, &'static str>(file)
    })
    .await
    .map_err(|e| ActionError::Internal(e.to_string()))?;
    got.map(|p| Some(json!({"path": p.display().to_string(), "fetched": true})))
        .map_err(|k| ActionError::Unavailable(k.into()))
}

/// Keeps at most `keep` files in `dir`: the oldest half goes when there are more.
fn trim(dir: &Path, keep: usize) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = rd
        .flatten()
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    if files.len() <= keep {
        return;
    }
    files.sort();
    for (_, p) in files.iter().take(files.len() / 2) {
        let _ = std::fs::remove_file(p);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SEARCH: &str = include_str!("../tests/fixtures/wallhaven-search.json");
    const INFO: &str = include_str!("../tests/fixtures/wallhaven-info.json");

    #[test]
    fn a_search_reply_parses_into_hits_and_paging() {
        let page = parse_search(SEARCH).unwrap();
        assert_eq!(page.page, 1);
        assert_eq!(page.last_page, 3);
        assert_eq!(page.total, 7);
        assert_eq!(page.seed.as_deref(), Some("aB3dE6"));
        // The fixture's third entry has no path: it is skipped, not shown broken.
        assert_eq!(page.hits.len(), 3);
        let h = &page.hits[0];
        assert_eq!(h.id, "94x38z");
        assert_eq!(h.thumb_url, "https://th.wallhaven.cc/small/94/94x38z.jpg");
        assert_eq!(h.full_url, "https://w.wallhaven.cc/full/94/wallhaven-94x38z.jpg");
        assert_eq!(h.resolution, "6742x3534");
        assert_eq!(h.file_size, 5_070_446);
        assert_eq!(h.category, "anime");
        assert_eq!(h.colors, ["#000000", "#abbcda", "#424153"]);
        assert_eq!(page.hits[1].purity, "sketchy");
        assert_eq!(ext_of(&page.hits[2].full_url), "png");
    }

    #[test]
    fn an_info_reply_and_errors_parse() {
        let h = parse_info(INFO).unwrap();
        assert_eq!(h.id, "6d71l7");
        assert_eq!(h.full_url, "https://w.wallhaven.cc/full/6d/wallhaven-6d71l7.png");
        assert_eq!(parse_info(r#"{"error":"Nothing here"}"#), Err(ERR_NOT_FOUND));
        assert_eq!(parse_search("<html>"), Err(ERR_REPLY));
        assert_eq!(parse_search(r#"{"meta":{}}"#), Err(ERR_REPLY));
        assert_eq!(parse_search(r#"{"error":"Unauthorized"}"#), Err(ERR_FAILED));
    }

    #[test]
    fn queries_are_checked_and_sfw_by_default() {
        let q = parse_query(&json!({}), false).unwrap();
        assert_eq!(
            (q.q.as_str(), q.categories.as_str(), q.purity.as_str(), q.sorting.as_str(), q.page),
            ("", "111", "100", "toplist", 1)
        );
        let q = parse_query(
            &json!({"query": " 夜 sky ", "categories": "010", "purity": "110", "sorting": "random", "page": 2, "seed": "aB3dE6"}),
            false,
        )
        .unwrap();
        assert_eq!(
            search_url("http://x", &q),
            "http://x/api/v1/search?categories=010&purity=110&sorting=random&page=2&q=%E5%A4%9C%20sky&seed=aB3dE6"
        );
        let bad = |a: Value| parse_query(&a, true).unwrap_err();
        assert_eq!(bad(json!({"categories": "000"})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(bad(json!({"purity": "1x0"})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(bad(json!({"sorting": "best"})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(bad(json!({"page": 0})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(bad(json!({"seed": "a;b"})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(bad(json!({"query": 3})), ActionError::Invalid(ERR_ARGS.into()));
        assert_eq!(
            parse_query(&json!({"purity": "111"}), false),
            Err(ActionError::Invalid(ERR_NSFW_KEY.into())),
            "NSFW needs the API key"
        );
        assert!(parse_query(&json!({"purity": "111"}), true).is_ok());
        assert!(search_url(BASE_DEFAULT, &parse_query(&json!({}), false).unwrap()).contains("topRange=1M"));
    }

    #[test]
    fn ids_and_extensions() {
        assert!(valid_id("94x38z"));
        assert!(!valid_id("../etc"));
        assert!(!valid_id(""));
        assert!(!valid_id("ABC"));
        assert_eq!(ext_of("https://w.wallhaven.cc/full/94/wallhaven-94x38z.jpg"), "jpg");
        assert_eq!(ext_of("https://x/a.webp?x=1"), "webp");
        assert_eq!(ext_of("https://x/a"), "jpg");
    }

    #[test]
    fn the_reply_names_local_thumbnails_and_saved_pictures() {
        let dir = std::env::temp_dir().join(format!("kurashi-wh-reply-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("wallhaven-94x38z.jpg"), b"x").unwrap();
        let page = parse_search(SEARCH).unwrap();
        let thumbs = vec![Some(PathBuf::from("/c/94x38z.jpg")), None];
        let v = reply_of(&page, &thumbs, &dir);
        assert_eq!(v["rows"][0]["thumb"], "/c/94x38z.jpg");
        assert_eq!(
            v["rows"][0]["local"],
            dir.join("wallhaven-94x38z.jpg").display().to_string()
        );
        assert_eq!(v["rows"][1]["thumb_error"], "mod-wallpaper.wallhaven.error.thumb");
        assert!(v["rows"][1].get("local").is_none());
        assert!(v["rows"][2].get("thumb").is_none(), "missing thumbs are not invented");
        assert_eq!(v["seed"], "aB3dE6");
        assert_eq!(v["last_page"], 3);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_api_key_and_the_switch_come_from_the_settings() {
        let (_, rx) = tokio::sync::watch::channel(kurashi_mod_api::Values::from_iter([
            ("wallhaven".to_string(), json!(false)),
            ("wallhaven_api_key".to_string(), json!("  k3y  ")),
        ]));
        let c = WhConfig::read(&Settings::new(rx));
        assert_eq!(
            c,
            WhConfig {
                on: false,
                key: Some("k3y".into())
            }
        );
        let (_, rx) = tokio::sync::watch::channel(kurashi_mod_api::Values::new());
        assert_eq!(
            WhConfig::read(&Settings::new(rx)),
            WhConfig { on: true, key: None }
        );
    }
}
