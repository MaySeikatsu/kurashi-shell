//! The mod catalogue's data (K155, W98; docs/ux/mod-catalogue.md): an index entry (`mods/<id>.toml` in the index
//! repository, the same shape inside `index.json`), the summary of what a mod reaches (written by the index's CI from
//! the mod's own manifest, never by its author), and `.source` — where an installed mod came from. Data only: fetching
//! and installing are the daemon's.

use std::collections::BTreeMap;
use std::path::Path;

use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};

use crate::contract::UseKind;
use crate::manifest::Manifest;

/// What a mod adds, reads, may reach and runs: the four groups a person reads before installing, and the ones an
/// update is compared in.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Summary {
    #[serde(default)]
    pub provides: Vec<String>,
    #[serde(default)]
    pub uses: Vec<String>,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub hosts: Vec<HostSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HostSummary {
    pub name: String,
    pub exec: String,
    /// `enabled`, `subscribed` or `action`.
    pub start: String,
}

impl Summary {
    pub fn of(m: &Manifest) -> Self {
        Summary {
            provides: m.provides.iter().map(ToString::to_string).collect(),
            uses: m
                .contract
                .uses
                .iter()
                .map(|u| {
                    let kind = match u.kind {
                        UseKind::Doc => "doc",
                        UseKind::Action => "action",
                        UseKind::Intent => "intent",
                    };
                    format!("{kind}:{}{}", u.id, if u.optional { "?" } else { "" })
                })
                .collect(),
            capabilities: m.capabilities.clone(),
            hosts: m
                .hosts
                .iter()
                .map(|h| HostSummary {
                    name: h.name.clone(),
                    exec: h.exec.clone(),
                    start: serde_json::to_value(h.start)
                        .ok()
                        .and_then(|v| v.as_str().map(str::to_owned))
                        .unwrap_or_default(),
                })
                .collect(),
        }
    }

    /// What `newer` reaches that this one does not, by group (an update's sheet lists it; empty: no sheet).
    pub fn gained(&self, newer: &Summary) -> Summary {
        let more = |old: &[String], new: &[String]| -> Vec<String> {
            new.iter().filter(|x| !old.contains(x)).cloned().collect()
        };
        Summary {
            provides: more(&self.provides, &newer.provides),
            uses: more(&self.uses, &newer.uses),
            capabilities: more(&self.capabilities, &newer.capabilities),
            hosts: newer
                .hosts
                .iter()
                .filter(|h| !self.hosts.contains(h))
                .cloned()
                .collect(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.provides.is_empty()
            && self.uses.is_empty()
            && self.capabilities.is_empty()
            && self.hosts.is_empty()
    }
}

/// Where a version's files are.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Source {
    Git { git: String, rev: String },
    Archive { archive: String },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Release {
    pub version: Version,
    /// The shell versions it was checked against.
    pub shell: VersionReq,
    pub source: Source,
    /// SRI hash of the unpacked tree ([`crate::nar::hash`]).
    pub hash: String,
    /// Written by the index's CI (`kurashi mod check --summary`); absent in a pull request's first push.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<Summary>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    /// By language (`en` is required).
    pub name: BTreeMap<String, String>,
    #[serde(default)]
    pub description: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub homepage: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub license: Option<String>,
    #[serde(rename = "version")]
    pub versions: Vec<Release>,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum IndexError {
    #[error("mods.index.error.parse: {0}")]
    Parse(String),
    #[error("mods.index.error.id")]
    Id,
    #[error("mods.index.error.name")]
    Name,
    #[error("mods.index.error.no_version")]
    NoVersion,
    #[error("mods.index.error.hash: {0}")]
    Hash(String),
    #[error("mods.index.error.source: {0}")]
    Source(String),
    #[error("mods.index.error.version_twice: {0}")]
    VersionTwice(String),
}

fn id_ok(s: &str) -> bool {
    (1..=32).contains(&s.len())
        && s.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// `sha256-` and 32 bytes of standard base64.
pub fn hash_ok(h: &str) -> bool {
    h.strip_prefix("sha256-").is_some_and(|b| {
        b.len() == 44
            && b.ends_with('=')
            && b.chars()
                .all(|c| c.is_ascii_alphanumeric() || "+/=".contains(c))
    })
}

impl Entry {
    /// One entry from its TOML, held to the index's rules: an id as a mod's, an English name, at least one version,
    /// each version once, a well-formed hash, a source over https with a full revision.
    pub fn parse(text: &str) -> Result<Entry, IndexError> {
        let e: Entry =
            toml::from_str(text).map_err(|e| IndexError::Parse(e.message().to_string()))?;
        e.validate()?;
        Ok(e)
    }

    pub fn validate(&self) -> Result<(), IndexError> {
        if !id_ok(&self.id) || crate::manifest::RESERVED_IDS.contains(&self.id.as_str()) {
            return Err(IndexError::Id);
        }
        if self.name.get("en").is_none_or(|n| n.trim().is_empty()) {
            return Err(IndexError::Name);
        }
        if self.versions.is_empty() {
            return Err(IndexError::NoVersion);
        }
        for (i, r) in self.versions.iter().enumerate() {
            if self.versions[..i].iter().any(|o| o.version == r.version) {
                return Err(IndexError::VersionTwice(r.version.to_string()));
            }
            if !hash_ok(&r.hash) {
                return Err(IndexError::Hash(r.version.to_string()));
            }
            let (url, rev_ok) = match &r.source {
                Source::Git { git, rev } => (
                    git,
                    rev.len() == 40 && rev.chars().all(|c| c.is_ascii_hexdigit()),
                ),
                Source::Archive { archive } => (archive, true),
            };
            if !url.starts_with("https://") || !rev_ok {
                return Err(IndexError::Source(r.version.to_string()));
            }
        }
        Ok(())
    }

    /// The newest version, whatever shell it needs.
    pub fn newest(&self) -> Option<&Release> {
        self.versions
            .iter()
            .max_by(|a, b| a.version.cmp(&b.version))
    }

    /// The newest version that fits shell `shell`; `None`: the entry is not for this version.
    pub fn best(&self, shell: &Version) -> Option<&Release> {
        self.versions
            .iter()
            .filter(|r| r.shell.matches(shell))
            .max_by(|a, b| a.version.cmp(&b.version))
    }

    pub fn release(&self, version: &Version) -> Option<&Release> {
        self.versions.iter().find(|r| &r.version == version)
    }
}

/// The whole index (`index.json`): every entry, by id.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Index {
    pub mods: Vec<Entry>,
}

impl Index {
    /// From `index.json`; an entry that breaks the rules is left out and named, the rest stay usable.
    pub fn parse(json: &str) -> Result<(Index, Vec<(String, IndexError)>), IndexError> {
        let raw: Index =
            serde_json::from_str(json).map_err(|e| IndexError::Parse(e.to_string()))?;
        let mut bad = Vec::new();
        let mods = raw
            .mods
            .into_iter()
            .filter_map(|e| match e.validate() {
                Ok(()) => Some(e),
                Err(err) => {
                    bad.push((e.id.clone(), err));
                    None
                }
            })
            .collect();
        Ok((Index { mods }, bad))
    }

    pub fn entry(&self, id: &str) -> Option<&Entry> {
        self.mods.iter().find(|e| e.id == id)
    }
}

/// `.source` in an installed mod's folder: where it came from, so an update knows what it has and Remove what it may
/// take. A folder without it was put there by hand (or made with `kurashi mod new`) and is never touched.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Installed {
    /// The index it came from (its URL), or `folder` / `git` for `mod add --from`.
    pub index: String,
    pub version: Version,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    pub hash: String,
    /// Unix seconds.
    pub at: i64,
    #[serde(default)]
    pub summary: Summary,
}

pub const SOURCE_FILE: &str = ".source";

impl Installed {
    pub fn read(dir: &Path) -> Option<Installed> {
        toml::from_str(&std::fs::read_to_string(dir.join(SOURCE_FILE)).ok()?).ok()
    }

    pub fn write(&self, dir: &Path) -> std::io::Result<()> {
        let text = toml::to_string(self).map_err(std::io::Error::other)?;
        std::fs::write(dir.join(SOURCE_FILE), text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEA: &str = r#"
id = "tea"
name = { en = "Tea timer", ja = "お茶タイマー" }
description = { en = "Steeping times in the bar." }
icon = "emoji_food_beverage"
license = "MIT"

[[version]]
version = "1.1.0"
shell = ">=0.4, <0.6"
source = { git = "https://example.org/kurashi-tea", rev = "4f2a9d0c1b3e5f60718293a4b5c6d7e8f9012345" }
hash = "sha256-WJcwdHFmdA3LZyQ7EC1b2pQZ3N3SParvyjlVk4IET58="

[version.summary]
provides = ["widget:tea"]
uses = ["doc:svc.clock"]
capabilities = []

[[version]]
version = "1.2.0"
shell = ">=0.6"
source = { archive = "https://example.org/tea-1.2.0.tar.gz" }
hash = "sha256-WJcwdHFmdA3LZyQ7EC1b2pQZ3N3SParvyjlVk4IET58="

[version.summary]
provides = ["widget:tea", "panel:tea"]
uses = ["doc:svc.clock", "doc:svc.media?"]
capabilities = ["network"]
hosts = [{ name = "main", exec = "tea-host", start = "subscribed" }]
"#;

    #[test]
    fn an_entry_offers_the_newest_version_that_fits_the_shell() {
        let e = Entry::parse(TEA).unwrap();
        let v = |s: &str| Version::parse(s).unwrap();
        assert_eq!(e.best(&v("0.4.0")).unwrap().version, v("1.1.0"));
        assert_eq!(e.best(&v("0.6.1")).unwrap().version, v("1.2.0"));
        assert!(e.best(&v("0.3.0")).is_none(), "not for this version");
        assert_eq!(e.newest().unwrap().version, v("1.2.0"));
        // What the update reaches that the installed one does not: the sheet's lines.
        let (old, new) = (
            e.versions[0].summary.clone().unwrap(),
            e.versions[1].summary.clone().unwrap(),
        );
        let gained = old.gained(&new);
        assert_eq!(gained.provides, ["panel:tea"]);
        assert_eq!(gained.uses, ["doc:svc.media?"]);
        assert_eq!(gained.capabilities, ["network"]);
        assert_eq!(gained.hosts[0].exec, "tea-host");
        assert!(new.gained(&new).is_empty(), "no change, no sheet");
    }

    #[test]
    fn an_entry_that_breaks_the_rules_is_refused_with_its_key() {
        let key = |text: &str| Entry::parse(text).unwrap_err().to_string();
        assert_eq!(
            key(&TEA.replace("id = \"tea\"", "id = \"Tea\"")),
            "mods.index.error.id"
        );
        assert_eq!(
            key(&TEA.replace(
                "sha256-WJcwdHFmdA3LZyQ7EC1b2pQZ3N3SParvyjlVk4IET58=",
                "sha256-abc"
            )),
            "mods.index.error.hash: 1.1.0"
        );
        assert_eq!(
            key(&TEA.replace(
                "https://example.org/kurashi-tea",
                "http://example.org/kurashi-tea"
            )),
            "mods.index.error.source: 1.1.0"
        );
        assert_eq!(
            key(&TEA.replace("4f2a9d0c1b3e5f60718293a4b5c6d7e8f9012345", "main")),
            "mods.index.error.source: 1.1.0"
        );
        assert_eq!(
            key(&TEA.replace("1.2.0\"\nshell", "1.1.0\"\nshell")),
            "mods.index.error.version_twice: 1.1.0"
        );
        assert_eq!(
            key("id = \"tea\"\nname = { ja = \"お茶\" }\nversion = []\n"),
            "mods.index.error.name"
        );
        // In an index, a broken entry is named and the others stay.
        let good = serde_json::to_string(&Entry::parse(TEA).unwrap()).unwrap();
        let bad = good.replace("\"id\":\"tea\"", "\"id\":\"Bad\"");
        let (index, left_out) = Index::parse(&format!("{{\"mods\":[{good},{bad}]}}")).unwrap();
        assert_eq!(index.mods.len(), 1);
        assert_eq!(left_out, [("Bad".to_string(), IndexError::Id)]);
        assert!(index.entry("tea").is_some());
    }

    /// The example index's entry passes the same rules as `tools/mod-index/build.py`'s lint.
    #[test]
    fn the_example_indexs_entry_is_well_formed() {
        let e = Entry::parse(include_str!(
            "../../../tools/mod-index/example/mods/tea.toml"
        ))
        .unwrap();
        assert_eq!(e.id, "tea");
        let r = e
            .best(&Version::parse(env!("CARGO_PKG_VERSION")).unwrap())
            .expect("fits this version");
        assert_eq!(r.summary.as_ref().unwrap().hosts[0].start, "subscribed");
        assert!(crate::index::hash_ok(&r.hash));
    }

    #[test]
    fn where_a_mod_came_from_is_written_and_read_back() {
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(
            Installed::read(tmp.path()),
            None,
            "made by hand: no .source"
        );
        let e = Entry::parse(TEA).unwrap();
        let r = &e.versions[0];
        let it = Installed {
            index: "https://example.org/index.json".into(),
            version: r.version.clone(),
            rev: Some("4f2a9d0c1b3e5f60718293a4b5c6d7e8f9012345".into()),
            hash: r.hash.clone(),
            at: 1_794_000_000,
            summary: r.summary.clone().unwrap(),
        };
        it.write(tmp.path()).unwrap();
        assert_eq!(Installed::read(tmp.path()), Some(it));
    }
}
