//! Font family chains resolve to the first installed family (Shōjiki: the token names a
//! font that is actually there).

use std::collections::HashSet;
use std::process::Command;

pub trait FontProvider {
    fn is_installed(&self, family: &str) -> bool;
}

/// CSS-style generic names always "exist": fontconfig maps them to something.
fn is_generic(f: &str) -> bool {
    matches!(
        f.to_ascii_lowercase().as_str(),
        "sans-serif" | "serif" | "monospace" | "system-ui"
    )
}

/// Result of resolving a chain: the family and, when it was not the first choice, why.
pub fn resolve_chain(chain: &[String], p: &dyn FontProvider) -> (String, Option<String>) {
    for (i, f) in chain.iter().enumerate() {
        if is_generic(f) || p.is_installed(f) {
            let note = (i > 0).then(|| format!("font: {} not installed, using {f}", chain[0]));
            return (f.clone(), note);
        }
    }
    let last = chain.last().cloned().unwrap_or_else(|| "sans-serif".into());
    (
        last.clone(),
        Some(format!(
            "font: none of [{}] installed, falling back to {last}",
            chain.join(", ")
        )),
    )
}

/// `fc-list : family` once, cached in memory.
pub struct FcList {
    families: HashSet<String>,
}

impl FcList {
    pub fn query() -> std::io::Result<FcList> {
        let o = Command::new("fc-list").args([":", "family"]).output()?;
        Ok(FcList::from_output(&String::from_utf8_lossy(&o.stdout)))
    }

    /// One line per face, `Family A,Family B` (aliases) possibly with `\-` escapes.
    pub fn from_output(s: &str) -> FcList {
        let families = s
            .lines()
            .flat_map(|l| l.split(','))
            .map(|f| f.trim().replace("\\-", "-").to_lowercase())
            .filter(|f| !f.is_empty())
            .collect();
        FcList { families }
    }
}

impl FontProvider for FcList {
    fn is_installed(&self, family: &str) -> bool {
        self.families.contains(&family.to_lowercase())
    }
}

/// Test double.
pub struct FakeFonts(pub Vec<String>);

impl FakeFonts {
    pub fn new(names: &[&str]) -> FakeFonts {
        FakeFonts(names.iter().map(|s| (*s).to_string()).collect())
    }
}

impl FontProvider for FakeFonts {
    fn is_installed(&self, family: &str) -> bool {
        self.0.iter().any(|f| f.eq_ignore_ascii_case(family))
    }
}
