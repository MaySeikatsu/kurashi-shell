//! K154: the bundled mods are held to the ruleset they are the example of, the docs' table of extension points is the
//! registry's, and the shell's slot hosts name registered slots only.

use std::path::{Path, PathBuf};

use kurashi_mods::{check, points};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// Mods the check cannot pass yet, each with the row that says why.
const PENDING: &[(&str, &str)] = &[(
    "easter-eggs",
    "BACKLOG I286: it declares action:easter.* and has no code, so no action to declare",
)];

#[test]
fn every_bundled_mod_passes_the_check() {
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(repo().join("mods"))
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.join("mod.toml").is_file())
        .collect();
    dirs.sort();
    assert!(dirs.len() >= 12, "the bundled mods were not found");
    let mut failed = String::new();
    for dir in dirs {
        let r = check::check_dir(&dir, &version);
        let pending = PENDING.iter().any(|(id, _)| *id == r.id);
        if r.passed() == pending {
            failed.push_str(&r.text());
            if pending {
                failed.push_str("  (it passes now: take it out of PENDING)\n");
            }
        }
    }
    assert!(failed.is_empty(), "\n{failed}");
}

#[test]
fn the_docs_table_of_points_is_the_registry() {
    let text = std::fs::read_to_string(repo().join("docs/MODS.md")).unwrap();
    let begin = text.find("<!-- points:begin").expect("points:begin");
    let begin = begin + text[begin..].find("-->").unwrap() + 4;
    let end = text.find("<!-- points:end -->").expect("points:end");
    assert_eq!(
        text[begin..end].trim(),
        points::markdown().trim(),
        "docs/MODS.md: paste `kurashi mod points --markdown` between the marks"
    );
}

fn qml(dir: &Path, out: &mut Vec<PathBuf>) {
    for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let p = e.path();
        if p.is_symlink() {
            continue;
        }
        if p.is_dir() {
            qml(&p, out);
        } else if p.extension().is_some_and(|x| x == "qml") {
            out.push(p);
        }
    }
}

#[test]
fn the_shells_slot_hosts_name_registered_slots() {
    let mut files = Vec::new();
    qml(&repo().join("frontend"), &mut files);
    let mut hosted = Vec::new();
    for f in files {
        for line in std::fs::read_to_string(&f).unwrap().lines() {
            let Some(i) = line.find("SlotHost {") else {
                continue;
            };
            let Some(j) = line[i..].find("slot: \"") else {
                continue;
            };
            let name = &line[i + j + 7..];
            let name = &name[..name.find('"').unwrap_or(0)];
            assert!(
                points::is_slot(name),
                "{}: SlotHost names `{name}`, which kurashi_mods::points::POINTS does not list",
                f.display()
            );
            hosted.push(name.to_owned());
        }
    }
    assert!(
        hosted.len() >= 6,
        "the shell's slot hosts were not found: {hosted:?}"
    );
}
