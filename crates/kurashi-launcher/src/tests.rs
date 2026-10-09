//! Integration-style tests over temp dirs. Nothing here spawns an application.

use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use super::*;

fn write(dir: &Path, file: &str, body: &str) {
    let p = dir.join(file);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, body).unwrap();
}

fn app(name: &str, extra: &str) -> String {
    format!(
        "[Desktop Entry]\nType=Application\nName={name}\nExec={}\n{extra}",
        name.to_lowercase().replace(' ', "-")
    )
}

fn cfg(dirs: Vec<std::path::PathBuf>) -> IndexConfig {
    IndexConfig {
        dirs,
        locale: None,
        desktops: vec!["niri".into()],
        check_try_exec: true,
    }
}

fn ids(r: &[QueryResult]) -> Vec<&str> {
    r.iter().map(|r| r.id.as_str()).collect()
}

fn fixture() -> (tempfile::TempDir, IndexConfig) {
    let t = tempfile::tempdir().unwrap();
    let d = t.path();
    write(
        d,
        "firefox.desktop",
        &app(
            "Firefox",
            "GenericName=Web Browser\nKeywords=internet;www;\nActions=win;\n[Desktop Action win]\nName=New Window\nExec=firefox --new-window\n",
        ),
    );
    write(
        d,
        "foot.desktop",
        &app("Foot", "GenericName=Terminal\nTerminal=false\n"),
    );
    write(
        d,
        "code.desktop",
        &app("Visual Studio Code", "Keywords=editor;ide;\n"),
    );
    write(d, "htop.desktop", &app("Htop", "Terminal=true\n"));
    write(d, "calc.desktop", &app("Calculator", ""));
    write(d, "hidden.desktop", &app("Hidden App", "NoDisplay=true\n"));
    write(d, "deleted.desktop", &app("Deleted App", "Hidden=true\n"));
    write(
        d,
        "gnome.desktop",
        &app("Gnome Only", "OnlyShowIn=GNOME;\n"),
    );
    write(d, "notniri.desktop", &app("Not Niri", "NotShowIn=niri;\n"));
    write(
        d,
        "missing.desktop",
        &app("Missing Tool", "TryExec=/nonexistent/tool\n"),
    );
    write(
        d,
        "present.desktop",
        &app("Present Tool", "TryExec=/bin/sh\n"),
    );
    write(
        d,
        "link.desktop",
        "[Desktop Entry]\nType=Link\nName=A Link\nURL=x\n",
    );
    write(d, "sub/nested.desktop", &app("Nested", ""));
    let c = cfg(vec![t.path().to_path_buf()]);
    (t, c)
}

fn launcher() -> (tempfile::TempDir, Launcher) {
    let (t, c) = fixture();
    let l = Launcher::new(
        c,
        LaunchOptions {
            terminal_cmd: vec!["foot".into(), "-e".into()],
            systemd_scope: false,
        },
        Frecency::memory(),
    );
    (t, l)
}

#[test]
fn visibility_rules() {
    let (_t, l) = launcher();
    let all = l.query("", 100);
    let got: Vec<&str> = all.iter().map(|r| r.name.as_str()).collect();
    for want in [
        "Firefox",
        "Foot",
        "Visual Studio Code",
        "Htop",
        "Calculator",
        "Present Tool",
        "Nested",
    ] {
        assert!(got.contains(&want), "missing {want}: {got:?}");
    }
    for no in [
        "Hidden App",
        "Deleted App",
        "Gnome Only",
        "Not Niri",
        "Missing Tool",
        "A Link",
    ] {
        assert!(!got.contains(&no), "should be hidden: {no}");
    }
    // Subdirectory -> id with '-'.
    assert!(ids(&all).contains(&"sub-nested"));
    // Actions never appear in the empty-query list.
    assert!(all.iter().all(|r| r.kind == Kind::App));
}

#[test]
fn earlier_dir_shadows_later_even_when_hidden() {
    let a = tempfile::tempdir().unwrap();
    let b = tempfile::tempdir().unwrap();
    write(a.path(), "x.desktop", &app("X User", ""));
    write(b.path(), "x.desktop", &app("X System", ""));
    write(a.path(), "y.desktop", &app("Y User", "Hidden=true\n"));
    write(b.path(), "y.desktop", &app("Y System", ""));
    let idx = Index::build(&cfg(vec![a.path().into(), b.path().into()]));
    assert_eq!(idx.app("x").unwrap().entry.name, "X User");
    assert!(idx.app("y").is_none());
}

#[test]
fn ranking_table() {
    let (_t, l) = launcher();
    // (query, expected top id)
    let table = [
        ("fire", "firefox"),
        ("vsc", "code"),
        ("studio", "code"),
        ("browser", "firefox"),  // generic name
        ("internet", "firefox"), // keyword
        ("calc", "calc"),
        ("htp", "htop"),
        ("ide", "code"),
    ];
    for (q, top) in table {
        let r = l.query(q, 5);
        assert_eq!(
            r.first().map(|r| r.id.as_str()),
            Some(top),
            "query {q:?} -> {:?}",
            ids(&r)
        );
    }
    assert!(l.query("zzzzqq", 5).is_empty());
}

#[test]
fn actions_match_and_rank_below_their_app() {
    let (_t, l) = launcher();
    let r = l.query("new window", 5);
    assert_eq!(r[0].id, "firefox:win");
    assert_eq!(r[0].kind, Kind::Action);
    assert_eq!(r[0].parent.as_deref(), Some("firefox"));
    let r = l.query("firefox", 5);
    assert_eq!(r[0].id, "firefox");
    assert!(r.iter().any(|x| x.id == "firefox:win"));
    assert!(r[0].score > r[1].score);
}

#[test]
fn frecency_reorders_close_matches() {
    let t = tempfile::tempdir().unwrap();
    write(t.path(), "a.desktop", &app("Terminal Alpha", ""));
    write(t.path(), "b.desktop", &app("Terminal Bravo", ""));
    let mut fr = Frecency::memory();
    let before = Launcher::new(
        cfg(vec![t.path().into()]),
        LaunchOptions::default(),
        Frecency::memory(),
    );
    assert_eq!(before.query("term", 2).first().unwrap().id, "a"); // name tie-break
    fr.record("b", 1000);
    fr.record("b", 1000);
    let l = Launcher::new(cfg(vec![t.path().into()]), LaunchOptions::default(), fr);
    let r = l.query_at("term", 2, 1000);
    assert_eq!(r[0].id, "b");
    // ... and decays away: a year later the tie-break wins again.
    let r = l.query_at("term", 2, 1000 + 365 * 86_400);
    assert_eq!(r[0].id, "a");
    // Empty query is ordered by frecency too.
    assert_eq!(l.query_at("", 2, 1000)[0].id, "b");
}

#[test]
fn frecency_cannot_beat_a_much_better_text_match() {
    let t = tempfile::tempdir().unwrap();
    write(t.path(), "exact.desktop", &app("Notes", ""));
    write(
        t.path(),
        "fuzzy.desktop",
        &app("Nautilus Open Terminal Editor Settings", ""),
    );
    let mut fr = Frecency::memory();
    for _ in 0..20 {
        fr.record("fuzzy", 0);
    }
    let l = Launcher::new(cfg(vec![t.path().into()]), LaunchOptions::default(), fr);
    assert_eq!(l.query_at("notes", 2, 0)[0].id, "exact");
}

#[test]
fn localised_names_are_indexed() {
    let t = tempfile::tempdir().unwrap();
    write(
        t.path(),
        "ff.desktop",
        "[Desktop Entry]\nType=Application\nName=Firefox\nName[ja]=ファイアフォックス\nExec=ff\n",
    );
    let mut c = cfg(vec![t.path().into()]);
    c.locale = Some("ja_JP.UTF-8".into());
    let l = Launcher::new(c, LaunchOptions::default(), Frecency::memory());
    let r = l.query("ファイ", 3);
    assert_eq!(r[0].name, "ファイアフォックス");
}

#[test]
fn result_json_shape() {
    let (_t, l) = launcher();
    let r = &l.query("firefox", 1)[0];
    let v = serde_json::to_value(r).unwrap();
    assert_eq!(v["id"], "firefox");
    assert_eq!(v["kind"], "app");
    assert_eq!(v["generic"], "Web Browser");
    assert!(v.get("parent").is_none());
    assert!(v["score"].is_number());
    let a = serde_json::to_value(&l.query("new window", 1)[0]).unwrap();
    assert_eq!(a["kind"], "action");
    assert_eq!(a["parent"], "firefox");
}

#[test]
fn command_for_apps_actions_terminal() {
    let (_t, l) = launcher();
    assert_eq!(l.command_for("firefox", &[]).unwrap(), ["firefox"]);
    assert_eq!(
        l.command_for("firefox:win", &[]).unwrap(),
        ["firefox", "--new-window"]
    );
    assert_eq!(l.command_for("htop", &[]).unwrap(), ["foot", "-e", "htop"]);
    assert!(matches!(
        l.command_for("nope", &[]),
        Err(LaunchError::UnknownId(_))
    ));
    assert!(matches!(
        l.command_for("firefox:nope", &[]),
        Err(LaunchError::UnknownId(_))
    ));
}

#[test]
fn reindex_picks_up_changes() {
    let (t, l) = launcher();
    let n = l.len();
    write(t.path(), "new.desktop", &app("Brand New", ""));
    assert_eq!(l.len(), n);
    l.reindex();
    assert_eq!(l.len(), n + 1);
    assert_eq!(l.query("brand", 1)[0].id, "new");
}

#[test]
fn inotify_reindexes_on_temp_dir_change() {
    let (t, l) = launcher();
    let (tx, rx) = mpsc::channel();
    let _w = l
        .watch(Duration::from_millis(50), move || {
            let _ = tx.send(());
        })
        .unwrap();

    // A burst of writes collapses into (at least one, typically one) callback.
    write(t.path(), "w1.desktop", &app("Watched One", ""));
    write(t.path(), "w2.desktop", &app("Watched Two", ""));
    rx.recv_timeout(Duration::from_secs(5))
        .expect("no change event for create");
    assert!(
        l.query("watched one", 1)
            .first()
            .is_some_and(|r| r.id == "w1")
    );
    assert!(
        l.query("watched two", 1)
            .first()
            .is_some_and(|r| r.id == "w2")
    );

    while rx.try_recv().is_ok() {}
    std::fs::remove_file(t.path().join("w1.desktop")).unwrap();
    rx.recv_timeout(Duration::from_secs(5))
        .expect("no change event for delete");
    assert!(l.query("watched one", 5).iter().all(|r| r.id != "w1"));

    // Files in a directory created after the watch started are seen too.
    while rx.try_recv().is_ok() {}
    std::fs::create_dir(t.path().join("late")).unwrap();
    rx.recv_timeout(Duration::from_secs(5))
        .expect("no event for new subdir");
    while rx.try_recv().is_ok() {}
    write(t.path(), "late/l.desktop", &app("Late Arrival", ""));
    rx.recv_timeout(Duration::from_secs(5))
        .expect("no event inside new subdir");
    assert_eq!(l.query("late arrival", 1)[0].id, "late-l");

    // Unrelated files are ignored (no callback).
    while rx.try_recv().is_ok() {}
    write(t.path(), "notes.txt", "x");
    assert!(rx.recv_timeout(Duration::from_millis(300)).is_err());
}

#[test]
fn watcher_drop_stops_threads_and_no_dirs_is_an_error() {
    let t = tempfile::tempdir().unwrap();
    let w = Watcher::new(&[t.path().into()], Duration::from_millis(10), || {}).unwrap();
    drop(w); // must not hang
    assert!(Watcher::new(&[t.path().join("absent")], Duration::from_millis(10), || {}).is_err());
}

#[test]
fn latency_bench_500_entries() {
    let t = tempfile::tempdir().unwrap();
    let words = [
        "Alpha", "Beta", "Gamma", "Delta", "Editor", "Viewer", "Player", "Studio", "Mail",
        "Browser", "Terminal", "Code",
    ];
    for i in 0..500 {
        let name = format!("{} {} {}", words[i % 12], words[(i * 7 + 3) % 12], i);
        write(
            t.path(),
            &format!("app{i}.desktop"),
            &app(
                &name,
                "Keywords=one;two;three;\nCategories=Utility;Network;\nActions=a;b;\n[Desktop Action a]\nName=Open New\nExec=x\n[Desktop Action b]\nName=Settings\nExec=y\n",
            ),
        );
    }
    let l = Launcher::new(
        cfg(vec![t.path().into()]),
        LaunchOptions::default(),
        Frecency::memory(),
    );
    assert_eq!(l.len(), 500);

    let queries = [
        "a", "ed", "br", "term", "stu pl", "xyz", "code 4", "vsc", "mailbr", "open new",
    ];
    for q in queries {
        l.query(q, 20); // warm up
    }
    let mut samples = Vec::new();
    for _ in 0..20 {
        for q in queries {
            let s = Instant::now();
            std::hint::black_box(l.query(q, 20));
            samples.push(s.elapsed());
        }
    }
    samples.sort();
    let p99 = samples[samples.len() * 99 / 100];
    // Budget is for release builds (BENCH); debug is ~40x slower, so scale the bound there.
    let budget = if cfg!(debug_assertions) {
        Duration::from_millis(150)
    } else {
        Duration::from_millis(2)
    };
    eprintln!("launcher query p99 = {p99:?} (budget {budget:?})");
    assert!(p99 < budget, "p99 {p99:?} over budget {budget:?}");
}
