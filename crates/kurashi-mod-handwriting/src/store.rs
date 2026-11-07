//! A person's fonts as they draw them (K94): one JSON file per font under `$XDG_DATA_HOME/kurashi/handwriting`, kept as strokes so a
//! font can be remade at another pen width; the made fonts go in the user's font folder, where fontconfig and Font Mix find them.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::font;
use crate::glyph::Strokes;

/// What the sequence asks for, in order: capitals, small letters, digits, then the marks a text needs. A mark left out falls back.
pub const CHARSET: &str =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?'\"-()&/+=@#%*";
pub const DEFAULT_PEN: f64 = 56.0;
pub const MAX_VERSIONS: u32 = 8;
/// 2: simple polygons. Fonts made before could crash the shell's text renderer (`glyph::outline`).
pub const OUTLINES: u32 = 2;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Font {
    pub name: String,
    pub pen: f64,
    /// How many versions of its letters this font asks for: each one is a font of its own, which Font Mix mixes.
    pub versions: u32,
    /// `"<version>:<char>"` → the drawing.
    pub glyphs: BTreeMap<String, Strokes>,
    /// Which outlines its files were made with (`OUTLINES`): older ones are made again on the next start.
    #[serde(default)]
    pub outlines: u32,
}

#[derive(Debug)]
pub struct Store {
    data: PathBuf,
    fonts_dir: PathBuf,
    pub fonts: BTreeMap<String, Font>,
}

fn slug(name: &str) -> String {
    let s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let s = s.trim_matches('-').to_owned();
    if s.is_empty() { "hand".into() } else { s }
}

impl Store {
    pub fn default_paths() -> (PathBuf, PathBuf) {
        let data = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
            .unwrap_or_else(|| PathBuf::from("."));
        (data.join("kurashi/handwriting"), data.join("fonts"))
    }

    pub fn load(data: PathBuf, fonts_dir: PathBuf) -> Self {
        let mut fonts = BTreeMap::new();
        if let Ok(rd) = std::fs::read_dir(&data) {
            for e in rd.flatten() {
                let p = e.path();
                let Some(id) = p.file_stem().and_then(|s| s.to_str()).map(String::from) else {
                    continue;
                };
                if p.extension().is_some_and(|x| x == "json")
                    && let Ok(text) = std::fs::read_to_string(&p)
                    && let Ok(f) = serde_json::from_str::<Font>(&text)
                {
                    fonts.insert(id, f);
                }
            }
        }
        Store {
            data,
            fonts_dir,
            fonts,
        }
    }

    fn save(&self, id: &str) -> Result<(), String> {
        let f = self.fonts.get(id).ok_or("handwriting.error.no_font")?;
        std::fs::create_dir_all(&self.data).map_err(|e| e.to_string())?;
        let tmp = self.data.join(format!("{id}.tmp"));
        let text = serde_json::to_string(f).map_err(|e| e.to_string())?;
        std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, self.data.join(format!("{id}.json"))).map_err(|e| e.to_string())
    }

    pub fn create(&mut self, name: &str) -> Result<String, String> {
        let name = name.trim();
        if name.is_empty() || name.chars().count() > 40 {
            return Err("handwriting.error.name".into());
        }
        let base = slug(name);
        let mut id = base.clone();
        let mut n = 2;
        while self.fonts.contains_key(&id) {
            id = format!("{base}-{n}");
            n += 1;
        }
        self.fonts.insert(
            id.clone(),
            Font {
                name: name.to_owned(),
                pen: DEFAULT_PEN,
                versions: 3,
                glyphs: BTreeMap::new(),
                outlines: OUTLINES,
            },
        );
        self.save(&id)?;
        Ok(id)
    }

    pub fn font_mut(&mut self, id: &str) -> Result<&mut Font, String> {
        self.fonts
            .get_mut(id)
            .ok_or_else(|| "handwriting.error.no_font".to_owned())
    }

    pub fn save_glyph(
        &mut self,
        id: &str,
        version: u32,
        c: char,
        strokes: Strokes,
    ) -> Result<(), String> {
        let f = self.font_mut(id)?;
        if version < 1 || version > f.versions {
            return Err("handwriting.error.version".into());
        }
        let key = format!("{version}:{c}");
        if strokes.iter().all(Vec::is_empty) {
            f.glyphs.remove(&key);
        } else {
            f.glyphs.insert(key, strokes);
        }
        self.save(id)
    }

    pub fn set_versions(&mut self, id: &str, n: u32) -> Result<(), String> {
        self.font_mut(id)?.versions = n.clamp(1, MAX_VERSIONS);
        self.save(id)
    }

    pub fn set_pen(&mut self, id: &str, pen: f64) -> Result<(), String> {
        self.font_mut(id)?.pen = pen.clamp(16.0, 160.0);
        self.save(id)
    }

    pub fn delete(&mut self, id: &str) -> Result<(), String> {
        let f = self.fonts.remove(id).ok_or("handwriting.error.no_font")?;
        let _ = std::fs::remove_file(self.data.join(format!("{id}.json")));
        for k in 1..=f.versions.max(MAX_VERSIONS) {
            let _ = std::fs::remove_file(self.file_of(id, k));
        }
        refresh_fontconfig(&self.fonts_dir);
        Ok(())
    }

    fn file_of(&self, id: &str, version: u32) -> PathBuf {
        self.fonts_dir
            .join(format!("kurashi-hand-{id}-{version}.ttf"))
    }

    /// The name a version's font goes by. One version takes the font's name alone.
    pub fn family_of(f: &Font, version: u32) -> String {
        if f.versions <= 1 {
            f.name.clone()
        } else {
            format!("{} {version}", f.name)
        }
    }

    /// Makes again the fonts on disk that older outlines made, and says which. A font that once took the shell down is never left
    /// in the fonts folder for the next start.
    pub fn refresh(&mut self) -> Vec<String> {
        let stale: Vec<String> = self
            .fonts
            .iter()
            .filter(|(_, f)| f.outlines < OUTLINES)
            .map(|(id, _)| id.clone())
            .collect();
        let mut made = Vec::new();
        for id in stale {
            let on_disk = (1..=MAX_VERSIONS).any(|k| self.file_of(&id, k).is_file());
            if on_disk && self.make(&id).is_ok() {
                made.push(id.clone());
            }
            if let Some(f) = self.fonts.get_mut(&id) {
                f.outlines = OUTLINES;
            }
            let _ = self.save(&id);
        }
        made
    }

    /// Makes the font of each version with something drawn in it (a version with nothing would only copy another). A letter a version
    /// has not drawn takes the first version that has: every version covers what any does, so a person can draw the whole set once and only
    /// the letters they care for again. Returns the families made.
    pub fn make(&self, id: &str) -> Result<Vec<String>, String> {
        let f = self.fonts.get(id).ok_or("handwriting.error.no_font")?;
        let mut made = Vec::new();
        std::fs::create_dir_all(&self.fonts_dir).map_err(|e| e.to_string())?;
        let has = |k: u32| {
            let prefix = format!("{k}:");
            f.glyphs.keys().any(|g| g.starts_with(&prefix))
        };
        for k in 1..=MAX_VERSIONS {
            if k > f.versions || !has(k) {
                let _ = std::fs::remove_file(self.file_of(id, k));
            }
        }
        for k in (1..=f.versions).filter(|k| has(*k)) {
            let mut letters: BTreeMap<char, &Strokes> = BTreeMap::new();
            for c in CHARSET.chars() {
                let own = f.glyphs.get(&format!("{k}:{c}"));
                let any = own
                    .or_else(|| (1..=f.versions).find_map(|v| f.glyphs.get(&format!("{v}:{c}"))));
                if let Some(s) = any {
                    letters.insert(c, s);
                }
            }
            let family = Self::family_of(f, k);
            let Some(bytes) = font::build(&letters, f.pen, &family)? else {
                continue;
            };
            let file = self.file_of(id, k);
            let tmp = file.with_extension("tmp");
            std::fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
            std::fs::rename(&tmp, &file).map_err(|e| e.to_string())?;
            made.push(family);
        }
        if made.is_empty() {
            return Err("handwriting.error.empty".into());
        }
        refresh_fontconfig(&self.fonts_dir);
        Ok(made)
    }

    /// The document: no strokes, they are fetched when a font is opened.
    pub fn document(&self) -> Value {
        let fonts: Vec<Value> = self
            .fonts
            .iter()
            .map(|(id, f)| {
                let done: Vec<usize> = (1..=f.versions)
                    .map(|k| {
                        let prefix = format!("{k}:");
                        f.glyphs.keys().filter(|g| g.starts_with(&prefix)).count()
                    })
                    .collect();
                let families: Vec<String> = (1..=f.versions)
                    .filter(|k| self.file_of(id, *k).is_file())
                    .map(|k| Self::family_of(f, k))
                    .collect();
                json!({"id": id, "name": f.name, "pen": f.pen, "versions": f.versions, "done": done, "families": families})
            })
            .collect();
        json!({
            "available": true,
            "fonts": fonts,
            "charset": CHARSET,
            "lines": {"cap": font::CAP, "x": font::X_HEIGHT, "ascent": font::ASCENT, "descent": font::DESCENT},
        })
    }
}

fn refresh_fontconfig(dir: &Path) {
    // (a new font is found on the next scan anyway; this makes that scan cheap, and failing it costs nothing)
    let _ = std::process::Command::new("fc-cache").arg(dir).output();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, Store) {
        let d = tempfile::tempdir().unwrap();
        let s = Store::load(d.path().join("hw"), d.path().join("fonts"));
        (d, s)
    }
    fn line() -> Strokes {
        vec![vec![[100.0, 0.0], [200.0, 480.0]]]
    }

    #[test]
    fn fonts_on_disk_from_older_outlines_are_made_again_once() {
        let (_d, mut st) = store();
        let id = st.create("old").unwrap();
        st.save_glyph(&id, 1, 'A', line()).unwrap();
        st.make(&id).unwrap();
        let file = st.file_of(&id, 1);
        std::fs::write(&file, b"not a font").unwrap();
        st.font_mut(&id).unwrap().outlines = 0;
        assert_eq!(st.refresh(), vec![id.clone()]);
        assert_ne!(std::fs::read(&file).unwrap(), b"not a font");
        assert_eq!(st.fonts[&id].outlines, OUTLINES);
        assert!(st.refresh().is_empty());
    }

    #[test]
    fn it_keeps_what_was_drawn_across_a_restart() {
        let (d, mut s) = store();
        let id = s.create("My Hand").unwrap();
        assert_eq!(id, "my-hand");
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        let again = Store::load(d.path().join("hw"), d.path().join("fonts"));
        assert_eq!(again.fonts[&id].glyphs["1:A"], line());
    }

    #[test]
    fn a_name_is_needed_and_two_fonts_may_share_one() {
        let (_d, mut s) = store();
        assert!(s.create("  ").is_err());
        assert_eq!(s.create("Hand").unwrap(), "hand");
        assert_eq!(s.create("Hand").unwrap(), "hand-2");
    }

    #[test]
    fn saving_nothing_takes_the_letter_back() {
        let (_d, mut s) = store();
        let id = s.create("H").unwrap();
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        s.save_glyph(&id, 1, 'A', vec![]).unwrap();
        assert!(s.fonts[&id].glyphs.is_empty());
    }

    #[test]
    fn a_version_out_of_range_is_refused() {
        let (_d, mut s) = store();
        let id = s.create("H").unwrap();
        assert!(s.save_glyph(&id, 9, 'A', line()).is_err());
    }

    /// Draw the whole set once, redraw only some: every version still covers every letter any version has.
    #[test]
    fn a_version_borrows_the_letters_it_has_not_drawn() {
        let (d, mut s) = store();
        let id = s.create("H").unwrap();
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        s.save_glyph(&id, 1, 'x', line()).unwrap();
        s.save_glyph(&id, 2, 'A', vec![vec![[0.0, 0.0], [400.0, 700.0]]])
            .unwrap();
        s.set_versions(&id, 2).unwrap();
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        let made = s.make(&id).unwrap();
        assert_eq!(made, vec!["H 1", "H 2"]);
        let two = std::fs::read(d.path().join("fonts/kurashi-hand-h-2.ttf")).unwrap();
        let f = skrifa::FontRef::new(&two).unwrap();
        use skrifa::MetadataProvider;
        assert!(f.charmap().map('x').is_some(), "borrowed from version 1");
        assert!(f.charmap().map('Q').is_none(), "not drawn by anyone");
    }

    #[test]
    fn nothing_drawn_makes_no_font_and_says_so() {
        let (_d, mut s) = store();
        let id = s.create("H").unwrap();
        assert_eq!(s.make(&id), Err("handwriting.error.empty".to_owned()));
    }

    #[test]
    fn the_document_says_how_far_each_version_is_without_the_strokes() {
        let (_d, mut s) = store();
        let id = s.create("H").unwrap();
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        let d = s.document();
        assert_eq!(d["fonts"][0]["done"], json!([1, 0, 0]));
        assert!(d["fonts"][0].get("glyphs").is_none());
        assert_eq!(d["fonts"][0]["families"], json!([]));
        s.make(&id).unwrap();
        // (only what has something drawn: versions 2 and 3 are still empty)
        assert_eq!(s.document()["fonts"][0]["families"], json!(["H 1"]));
    }

    #[test]
    fn deleting_a_font_takes_its_files_too() {
        let (d, mut s) = store();
        let id = s.create("H").unwrap();
        s.save_glyph(&id, 1, 'A', line()).unwrap();
        s.make(&id).unwrap();
        s.delete(&id).unwrap();
        assert!(!d.path().join("fonts/kurashi-hand-h-1.ttf").exists());
        assert!(!d.path().join("hw/h.json").exists());
    }
}
