//! The clipboard history (`;`, K44, W26) over cliphist, with image thumbnails and pins.
//!
//! Copied where others solved it: the list format and its `[[ binary data <size> <format> <w>x<h> ]]` image lines from
//! ii (`services/Cliphist.qml`, `entryIsImage`) and Noctalia (`Services/CliphistService.qml`: `cliphist list
//! -preview-width`, `cliphist decode <id> | wl-copy`, `cliphist wipe`); `cliphist delete` reads the entry's line on stdin
//! (ii's `deleteEntry`). Thumbnails differ on purpose: Noctalia keeps base64 data URLs in memory; here an image is
//! decoded once, scaled down to at most [`THUMB_PX`] and kept as `<cache>/<id>.png`, only when its row is shown (the
//! view asks), and removed when the entry leaves the history (Ma). Pins are DMS's (`ClipboardService.qml`: pinned
//! entries listed first, kept through "clear history"); here their content lives in the daemon's state dir, so a pin
//! survives cliphist's own pruning and a wipe.

use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

/// Longest side of a thumbnail.
pub const THUMB_PX: u32 = 256;
/// Larger entries are not decoded for a thumbnail or kept as a pin.
pub const MAX_BYTES: usize = 32 << 20;
/// Larger images (pixels) are not decoded.
pub const MAX_PIXELS: u64 = 64_000_000;
/// The preview width asked of `cliphist list` (characters): enough for two lines of a row.
pub const PREVIEW_CHARS: usize = 240;
/// At most this many pins.
pub const MAX_PINS: usize = 50;

#[derive(Debug, Clone, PartialEq)]
pub struct ImageInfo {
    /// As cliphist writes it: `12 KiB`.
    pub size: String,
    /// `png`, `jpeg`, `webp`, `gif`, `bmp`.
    pub format: String,
    pub w: u32,
    pub h: u32,
}

impl ImageInfo {
    pub fn mime(&self) -> String {
        format!("image/{}", self.format)
    }
}

/// One line of `cliphist list`.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub id: String,
    /// The line as listed (what `cliphist delete` reads back).
    pub line: String,
    /// The preview text (cliphist collapses whitespace and cuts it at the preview width).
    pub text: String,
    pub image: Option<ImageInfo>,
    /// `[[ binary data … ]]` that is not an image.
    pub binary: bool,
}

/// Parses `cliphist list` output: `<id>\t<preview>` per line, newest first. Lines without an id are skipped.
pub fn parse_list(out: &str) -> Vec<Entry> {
    out.lines()
        .filter_map(|line| {
            let (id, text) = line.split_once('\t')?;
            if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let bin = binary_info(text);
            Some(Entry {
                id: id.to_owned(),
                line: line.to_owned(),
                text: text.to_owned(),
                binary: bin.is_some(),
                image: bin.flatten(),
            })
        })
        .collect()
}

/// `[[ binary data 12 KiB png 640x480 ]]` → Some(Some(image)); `[[ binary data 3 KiB ]]` (not an image) → Some(None).
fn binary_info(text: &str) -> Option<Option<ImageInfo>> {
    let inner = text.trim().strip_prefix("[[")?.strip_suffix("]]")?.trim();
    let rest = inner.strip_prefix("binary data")?.trim();
    let words: Vec<&str> = rest.split_whitespace().collect();
    // `<num> <unit> <format> <w>x<h>`
    let dims = words.last().and_then(|d| {
        let (w, h) = d.split_once('x')?;
        Some((w.parse::<u32>().ok()?, h.parse::<u32>().ok()?))
    });
    Some(match (dims, words.len()) {
        (Some((w, h)), n) if n >= 4 => Some(ImageInfo {
            size: words[..n - 2].join(" "),
            format: words[n - 2].to_lowercase(),
            w,
            h,
        }),
        _ => None,
    })
}

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum ClipError {
    /// cliphist (or wl-copy) is not installed or did not answer.
    #[error("{0} is not available")]
    Missing(&'static str),
    /// No such entry (any more).
    #[error("no such clipboard entry")]
    Gone,
    #[error("the entry is too large")]
    TooLarge,
    #[error("not an image")]
    NotImage,
    #[error("too many pins")]
    PinsFull,
    #[error("{0}")]
    Failed(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct Pin {
    key: String,
    /// `text` or `image`.
    kind: String,
    #[serde(default)]
    text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    format: Option<String>,
    #[serde(default)]
    w: u32,
    #[serde(default)]
    h: u32,
    #[serde(default)]
    size: String,
    /// The cliphist id it was pinned from (its history row is not listed twice).
    #[serde(default)]
    src: String,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct PinFile {
    version: u32,
    pins: Vec<Pin>,
}

/// The clipboard mode: cliphist, the thumbnail cache and the pins.
#[derive(Debug, Clone)]
pub struct Clip {
    /// The cliphist binary (looked up in PATH).
    pub cliphist: String,
    pub wl_copy: String,
    cache: PathBuf,
    pins: PathBuf,
}

/// FNV-1a: a stable key for a pin's bytes (pinning the same thing twice is one pin).
fn hash(bytes: &[u8]) -> String {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    format!("{h:016x}")
}

impl Clip {
    /// Thumbnails under `cache` (`$XDG_CACHE_HOME/kurashi/clip`), pins under `pins` (`<state>/clip-pins`).
    pub fn new(cache: PathBuf, pins: PathBuf) -> Self {
        Self {
            cliphist: "cliphist".into(),
            wl_copy: "wl-copy".into(),
            cache,
            pins,
        }
    }

    fn list(&self) -> Result<Vec<Entry>, ClipError> {
        let out = Command::new(&self.cliphist)
            .args(["list", "-preview-width", &PREVIEW_CHARS.to_string()])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .map_err(|_| ClipError::Missing("cliphist"))?;
        if !out.status.success() {
            return Err(ClipError::Missing("cliphist"));
        }
        Ok(parse_list(&String::from_utf8_lossy(&out.stdout)))
    }

    fn decode(&self, id: &str) -> Result<Vec<u8>, ClipError> {
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
            return Err(ClipError::Gone);
        }
        let out = Command::new(&self.cliphist)
            .args(["decode", id])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .map_err(|_| ClipError::Missing("cliphist"))?;
        if !out.status.success() {
            return Err(ClipError::Gone);
        }
        Ok(out.stdout)
    }

    fn pin_file(&self) -> PathBuf {
        self.pins.join("pins.json")
    }

    fn load_pins(&self) -> Vec<Pin> {
        std::fs::read(self.pin_file())
            .ok()
            .and_then(|b| serde_json::from_slice::<PinFile>(&b).ok())
            .map(|f| f.pins)
            .unwrap_or_default()
    }

    fn save_pins(&self, pins: Vec<Pin>) -> Result<(), ClipError> {
        let fail = |e: std::io::Error| ClipError::Failed(e.to_string());
        std::fs::create_dir_all(&self.pins).map_err(fail)?;
        let tmp = self.pins.join("pins.json.tmp");
        let body = serde_json::to_vec(&PinFile { version: 1, pins })
            .map_err(|e| ClipError::Failed(e.to_string()))?;
        std::fs::write(&tmp, body).map_err(fail)?;
        std::fs::rename(&tmp, self.pin_file()).map_err(fail)
    }

    fn thumb_path(&self, id: &str) -> PathBuf {
        self.cache.join(format!("{id}.png"))
    }

    /// Drops cached thumbnails of entries no longer in `live` (the history changed, or was wiped).
    fn prune(&self, live: &[Entry]) {
        let Ok(dir) = std::fs::read_dir(&self.cache) else {
            return;
        };
        for f in dir.flatten() {
            let name = f.file_name().to_string_lossy().into_owned();
            let id = name.strip_suffix(".png").unwrap_or(&name);
            if !live.iter().any(|e| e.id == id) {
                let _ = std::fs::remove_file(f.path());
            }
        }
    }

    /// The rows for the query after `;`: pins first, then the history (newest first), then a "clear history" row
    /// (while the query is empty and there is history). Text rows carry their preview; image rows `image: {w, h,
    /// format, size}` and `thumb` (the cached file, "" until the view asks for it). A note row explains a missing
    /// cliphist or an empty history (Shōjiki).
    pub fn rows(&self, q: &str, limit: usize) -> Vec<Value> {
        let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
        let hit = |hay: &str| {
            let hay = hay.to_lowercase();
            words.iter().all(|w| hay.contains(w.as_str()))
        };
        let pins = self.load_pins();
        let mut rows: Vec<Value> = pins
            .iter()
            .filter(|p| hit(&format!("{} {} {}", p.text, p.kind, p.format.as_deref().unwrap_or(""))))
            .map(|p| {
                let mut r = json!({"id": format!("clip:pin:{}", p.key), "name": p.text, "kind": "clip",
                                   "pinned": true, "icon": null, "score": 1.0});
                if p.kind == "image" {
                    let fmt = p.format.clone().unwrap_or_default();
                    r["name"] = json!(format!("{} × {} {}", p.w, p.h, fmt.to_uppercase()));
                    r["generic"] = json!(p.size);
                    r["image"] = json!({"w": p.w, "h": p.h, "format": fmt, "size": p.size});
                    r["thumb"] = json!(self.pins.join(format!("{}.png", p.key)).display().to_string());
                }
                r
            })
            .collect();
        let history = match self.list() {
            Ok(h) => h,
            Err(_) => {
                rows.push(note("launcher.clip.unavailable"));
                return rows;
            }
        };
        self.prune(&history);
        let mut shown = 0;
        for e in history
            .iter()
            .filter(|e| !pins.iter().any(|p| p.src == e.id))
        {
            if shown >= limit {
                break;
            }
            let r = match &e.image {
                Some(img) => {
                    if !hit(&format!("image {} {}", img.format, e.text)) {
                        continue;
                    }
                    let t = self.thumb_path(&e.id);
                    json!({"id": format!("clip:{}", e.id), "name": format!("{} × {} {}", img.w, img.h, img.format.to_uppercase()),
                           "generic": img.size, "kind": "clip", "icon": null, "score": 1.0,
                           "image": {"w": img.w, "h": img.h, "format": img.format, "size": img.size},
                           "thumb": if t.is_file() { t.display().to_string() } else { String::new() }})
                }
                None => {
                    if !hit(&e.text) {
                        continue;
                    }
                    let mut r = json!({"id": format!("clip:{}", e.id), "name": e.text, "kind": "clip",
                                       "icon": null, "score": 1.0});
                    if e.binary {
                        r["binary"] = json!(true);
                    }
                    r
                }
            };
            rows.push(r);
            shown += 1;
        }
        if history.is_empty() && pins.is_empty() && words.is_empty() {
            return vec![note("launcher.clip.empty")];
        }
        if !history.is_empty() && words.is_empty() {
            rows.push(json!({"id": "clipclear:", "name": "launcher.clip.clear", "kind": "clipclear",
                             "count": history.len(), "pins": pins.len(), "icon": null, "score": 0.0}));
        }
        rows
    }

    /// The thumbnail of history entry `id` (decoded once, then the cached file).
    pub fn thumb(&self, id: &str) -> Result<PathBuf, ClipError> {
        let path = self.thumb_path(id);
        if path.is_file() {
            return Ok(path);
        }
        let bytes = self.decode(id)?;
        write_thumb(&bytes, &path)?;
        Ok(path)
    }

    /// Removes history entry `id` (`cliphist delete`), or the pin `pin:<key>`.
    pub fn delete(&self, id: &str) -> Result<(), ClipError> {
        if let Some(key) = id.strip_prefix("pin:") {
            return self.unpin(key);
        }
        let e = self
            .list()?
            .into_iter()
            .find(|e| e.id == id)
            .ok_or(ClipError::Gone)?;
        let mut child = Command::new(&self.cliphist)
            .arg("delete")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| ClipError::Missing("cliphist"))?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{}", e.line);
        }
        let ok = child.wait().map(|s| s.success()).unwrap_or(false);
        let _ = std::fs::remove_file(self.thumb_path(id));
        if ok {
            Ok(())
        } else {
            Err(ClipError::Failed("cliphist delete failed".into()))
        }
    }

    /// Wipes the history (`cliphist wipe`) and its thumbnails; pins stay.
    pub fn clear(&self) -> Result<(), ClipError> {
        let ok = Command::new(&self.cliphist)
            .arg("wipe")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|_| ClipError::Missing("cliphist"))?
            .success();
        self.prune(&[]);
        if ok {
            Ok(())
        } else {
            Err(ClipError::Failed("cliphist wipe failed".into()))
        }
    }

    /// Pins history entry `id`, or unpins it when it is pinned (`pin:<key>` always unpins). Answers whether it is
    /// pinned now.
    pub fn toggle_pin(&self, id: &str) -> Result<bool, ClipError> {
        let pins = self.load_pins();
        if let Some(key) = id.strip_prefix("pin:") {
            self.unpin(key)?;
            return Ok(false);
        }
        if let Some(p) = pins.iter().find(|p| p.src == id) {
            self.unpin(&p.key.clone())?;
            return Ok(false);
        }
        if pins.len() >= MAX_PINS {
            return Err(ClipError::PinsFull);
        }
        let entry = self
            .list()?
            .into_iter()
            .find(|e| e.id == id)
            .ok_or(ClipError::Gone)?;
        let bytes = self.decode(id)?;
        if bytes.len() > MAX_BYTES {
            return Err(ClipError::TooLarge);
        }
        let key = hash(&bytes);
        let mut pins = pins;
        if pins.iter().any(|p| p.key == key) {
            return Ok(true);
        }
        let fail = |e: std::io::Error| ClipError::Failed(e.to_string());
        std::fs::create_dir_all(&self.pins).map_err(fail)?;
        let pin = match &entry.image {
            Some(img) => {
                std::fs::write(self.pins.join(format!("{key}.bin")), &bytes).map_err(fail)?;
                write_thumb(&bytes, &self.pins.join(format!("{key}.png")))?;
                Pin {
                    key: key.clone(),
                    kind: "image".into(),
                    text: String::new(),
                    format: Some(img.format.clone()),
                    w: img.w,
                    h: img.h,
                    size: img.size.clone(),
                    src: id.to_owned(),
                }
            }
            None if entry.binary => return Err(ClipError::NotImage),
            None => Pin {
                key: key.clone(),
                kind: "text".into(),
                text: String::from_utf8_lossy(&bytes).into_owned(),
                format: None,
                w: 0,
                h: 0,
                size: String::new(),
                src: id.to_owned(),
            },
        };
        pins.insert(0, pin);
        self.save_pins(pins)?;
        Ok(true)
    }

    fn unpin(&self, key: &str) -> Result<(), ClipError> {
        let mut pins = self.load_pins();
        let before = pins.len();
        pins.retain(|p| p.key != key);
        if pins.len() == before {
            return Err(ClipError::Gone);
        }
        for ext in ["bin", "png"] {
            let _ = std::fs::remove_file(self.pins.join(format!("{key}.{ext}")));
        }
        self.save_pins(pins)
    }

    /// What copying `id` puts on the clipboard: its bytes and their mime type (None: let wl-copy tell). A pin
    /// (`pin:<key>`) from the state dir, a history entry decoded by cliphist.
    pub fn content(&self, id: &str) -> Result<(Vec<u8>, Option<String>), ClipError> {
        if let Some(key) = id.strip_prefix("pin:") {
            let p = self
                .load_pins()
                .into_iter()
                .find(|p| p.key == key)
                .ok_or(ClipError::Gone)?;
            return match p.kind.as_str() {
                "image" => {
                    let b = std::fs::read(self.pins.join(format!("{key}.bin")))
                        .map_err(|_| ClipError::Gone)?;
                    Ok((b, p.format.map(|f| format!("image/{f}"))))
                }
                _ => Ok((p.text.into_bytes(), Some("text/plain;charset=utf-8".into()))),
            };
        }
        let image = self
            .list()?
            .into_iter()
            .find(|e| e.id == id)
            .and_then(|e| e.image);
        Ok((self.decode(id)?, image.map(|i| i.mime())))
    }

    /// Puts entry `id` back on the clipboard (`wl-copy`, with the image's type).
    pub fn copy(&self, id: &str) -> Result<(), ClipError> {
        let (bytes, mime) = self.content(id)?;
        let mut cmd = Command::new(&self.wl_copy);
        if let Some(m) = &mime {
            cmd.args(["--type", m]);
        }
        let mut child = cmd
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| ClipError::Missing("wl-copy"))?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(&bytes)
                .map_err(|e| ClipError::Failed(e.to_string()))?;
        }
        // wl-copy forks to serve the clipboard; the parent exits once it has read its input.
        let _ = child.wait();
        Ok(())
    }
}

fn note(key: &str) -> Value {
    json!({"id": "", "name": key, "icon": null, "kind": "note", "score": 0.0})
}

/// Decodes an image and writes it scaled down to [`THUMB_PX`] as PNG at `path` (atomically).
fn write_thumb(bytes: &[u8], path: &Path) -> Result<(), ClipError> {
    if bytes.len() > MAX_BYTES {
        return Err(ClipError::TooLarge);
    }
    let reader = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| ClipError::NotImage)?;
    let (w, h) = reader.into_dimensions().map_err(|_| ClipError::NotImage)?;
    if u64::from(w) * u64::from(h) > MAX_PIXELS {
        return Err(ClipError::TooLarge);
    }
    let img = image::load_from_memory(bytes).map_err(|_| ClipError::NotImage)?;
    let small = if w > THUMB_PX || h > THUMB_PX {
        img.thumbnail(THUMB_PX, THUMB_PX)
    } else {
        img
    };
    let fail = |e: std::io::Error| ClipError::Failed(e.to_string());
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(fail)?;
    }
    let tmp = path.with_extension("png.tmp");
    small
        .save_with_format(&tmp, image::ImageFormat::Png)
        .map_err(|e| ClipError::Failed(e.to_string()))?;
    std::fs::rename(&tmp, path).map_err(fail)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn list_parses_text_image_and_binary_lines() {
        let out = "9\thello  world\n8\t[[ binary data 12 KiB png 640x480 ]]\n7\t[[ binary data 1.5 MiB jpeg 4000x3000 ]]\n\
                   6\t[[ binary data 3 KiB ]]\nnot a line\n\t\n5\tlast\n";
        let e = parse_list(out);
        assert_eq!(e.len(), 5);
        assert_eq!(e[0].text, "hello  world");
        assert!(e[0].image.is_none() && !e[0].binary);
        let img = e[1].image.as_ref().unwrap();
        assert_eq!(
            (img.size.as_str(), img.format.as_str(), img.w, img.h),
            ("12 KiB", "png", 640, 480)
        );
        assert_eq!(e[2].image.as_ref().unwrap().size, "1.5 MiB");
        assert_eq!(e[2].image.as_ref().unwrap().mime(), "image/jpeg");
        assert!(e[3].binary && e[3].image.is_none());
        assert_eq!(e[4].id, "5");
        assert_eq!(e[1].line, "8\t[[ binary data 12 KiB png 640x480 ]]");
    }

    /// A fake cliphist over a directory: `<dir>/<id>` files hold the entries, `list` prints them newest first.
    fn fake(dir: &Path) -> Clip {
        let bin = dir.join("cliphist");
        std::fs::write(
            &bin,
            r#"#!/bin/sh
d=$(dirname "$0")/db
case "$1" in
  list) for f in $(ls "$d" | grep -v preview | sort -rn); do printf '%s\t%s\n' "$f" "$(cat "$d/$f.preview")"; done ;;
  decode) cat "$d/$2" ;;
  delete) read -r line; id=${line%%	*}; rm -f "$d/$id" "$d/$id.preview"; echo "$id" >> "$d/../deleted" ;;
  wipe) rm -f "$d"/* ;;
esac
"#,
        )
        .unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::fs::create_dir_all(dir.join("db")).unwrap();
        let mut c = Clip::new(dir.join("cache"), dir.join("state/clip-pins"));
        c.cliphist = bin.display().to_string();
        c
    }

    fn put(dir: &Path, id: u32, bytes: &[u8], preview: &str) {
        std::fs::write(dir.join(format!("db/{id}")), bytes).unwrap();
        std::fs::write(dir.join(format!("db/{id}.preview")), preview).unwrap();
    }

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbImage::from_pixel(w, h, image::Rgb([200, 40, 60]));
        let mut out = std::io::Cursor::new(Vec::new());
        img.write_to(&mut out, image::ImageFormat::Png).unwrap();
        out.into_inner()
    }

    #[test]
    fn rows_thumbs_pins_delete_and_clear() {
        let d = tempfile::tempdir().unwrap();
        let c = fake(d.path());
        assert_eq!(c.rows("", 40)[0]["name"], "launcher.clip.empty");
        put(d.path(), 1, b"first text", "first text");
        put(
            d.path(),
            2,
            &png(600, 300),
            "[[ binary data 1 KiB png 600x300 ]]",
        );
        put(d.path(), 3, b"third\nline", "third line");
        let rows = c.rows("", 40);
        let ids: Vec<&str> = rows.iter().map(|r| r["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["clip:3", "clip:2", "clip:1", "clipclear:"]);
        assert_eq!(rows[1]["image"]["w"], 600);
        assert_eq!(rows[1]["thumb"], "", "no thumbnail until the view asks");
        assert_eq!(rows[3]["count"], 3);

        let t = c.thumb("2").unwrap();
        let small = image::open(&t).unwrap();
        assert_eq!((small.width(), small.height()), (256, 128));
        assert_eq!(c.rows("", 40)[1]["thumb"], t.display().to_string());
        assert_eq!(c.thumb("1"), Err(ClipError::NotImage));
        assert_eq!(c.thumb("99"), Err(ClipError::Gone));

        // Filter, limit.
        assert_eq!(c.rows("third", 40).len(), 1);
        assert_eq!(c.rows("png", 40)[0]["id"], "clip:2");
        assert_eq!(c.rows("", 1).len(), 2, "one entry and the clear row");

        // Pins: listed first, their history row not twice; kept through a wipe; copied from the state dir.
        assert!(c.toggle_pin("1").unwrap());
        assert!(c.toggle_pin("2").unwrap());
        let rows = c.rows("", 40);
        assert_eq!(rows[0]["pinned"], true);
        assert_eq!(rows[0]["image"]["format"], "png");
        assert_eq!(rows[1]["name"], "first text");
        assert_eq!(rows[2]["id"], "clip:3");
        assert_eq!(rows.iter().filter(|r| r["id"] == "clip:1").count(), 0);
        let key = rows[1]["id"]
            .as_str()
            .unwrap()
            .strip_prefix("clip:")
            .unwrap()
            .to_owned();
        assert_eq!(c.content(&key).unwrap().0, b"first text");
        let ikey = rows[0]["id"]
            .as_str()
            .unwrap()
            .strip_prefix("clip:")
            .unwrap()
            .to_owned();
        assert_eq!(c.content(&ikey).unwrap().1.as_deref(), Some("image/png"));
        assert_eq!(c.content("2").unwrap().1.as_deref(), Some("image/png"));

        // Delete: the line goes to cliphist on stdin, its thumbnail goes too.
        c.delete("2").unwrap();
        assert_eq!(
            std::fs::read_to_string(d.path().join("deleted"))
                .unwrap()
                .trim(),
            "2"
        );
        assert!(!t.exists());
        assert_eq!(c.delete("2"), Err(ClipError::Gone));

        c.clear().unwrap();
        let rows = c.rows("", 40);
        assert_eq!(rows.len(), 2, "both pins survive the wipe: {rows:?}");
        assert!(rows.iter().all(|r| r["kind"] != "clipclear"));
        // Unpin by the pin id.
        assert!(!c.toggle_pin(&ikey).unwrap());
        c.delete(&key).unwrap();
        assert_eq!(c.rows("", 40)[0]["name"], "launcher.clip.empty");
    }

    #[test]
    fn missing_cliphist_is_a_note_and_pins_still_show() {
        let d = tempfile::tempdir().unwrap();
        let mut c = Clip::new(d.path().join("cache"), d.path().join("pins"));
        c.cliphist = d.path().join("no-such-cliphist").display().to_string();
        assert_eq!(c.rows("", 40), vec![note("launcher.clip.unavailable")]);
        assert_eq!(c.thumb("1"), Err(ClipError::Missing("cliphist")));
    }

    #[test]
    fn huge_images_are_refused() {
        let d = tempfile::tempdir().unwrap();
        let big = vec![0u8; MAX_BYTES + 1];
        assert_eq!(
            write_thumb(&big, &d.path().join("x.png")),
            Err(ClipError::TooLarge)
        );
    }
}
