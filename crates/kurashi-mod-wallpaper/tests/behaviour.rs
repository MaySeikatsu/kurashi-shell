//! The wallpaper mod through its registrations, against a recording fake backend (no processes).
//! Acceptance of W12-wallpaper: enable starts the daemon once; `set` runs `img` with the card's
//! flags; next and prev cycle the library; a missing binary disables its choice with a reason; rotation
//! applies one image per minute on a paused clock and stops with the mod; a restart restores the
//! stored images; no work happens while the picker is closed and rotation is off.

mod common;

use std::time::Duration;

use common::{Fake, Mod, choices_by_value, eventually, library, scratch, values};
use kurashi_mod_wallpaper::Dirs;
use serde_json::{Value, json};

const FLAGS: &str = "--resize crop --crop-gravity center --transition-type fade \
                     --transition-duration 1.00 --transition-angle 45";

fn state_file(dirs: &Dirs) -> std::path::PathBuf {
    dirs.state_file()
}

/// Waits until the supervisor has looked at the backend once (the document is `loaded`).
async fn loaded(m: &Mod) {
    eventually(|| m.doc()["loaded"] == true).await;
}

#[tokio::test]
async fn enable_starts_the_daemon_once_and_publishes_the_outputs() {
    let root = scratch("enable");
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&root)).unwrap();
    m.subscribe();
    loaded(&m).await;

    assert_eq!(
        fake.count("spawn awww-daemon --no-cache"),
        1,
        "started once"
    );
    let doc = m.doc();
    assert_eq!(doc["available"], true);
    assert_eq!(doc["backend"]["available"], true);
    assert_eq!(doc["backend"]["version"], "0.12.1");
    assert!(
        doc["backend"].get("reason").is_none(),
        "no reason when it works"
    );
    assert_eq!(doc["outputs"]["DP-1"]["width"], 2560);
    assert_eq!(
        doc["outputs"]["DP-2"]["path"],
        Value::Null,
        "nothing set there yet"
    );
    assert_eq!(doc["library"]["count"], 0, "an empty folder");
    assert_eq!(
        doc["library"]["folders"][0]["reason"],
        "mod-wallpaper.folder.empty"
    );
}

#[tokio::test]
async fn set_runs_img_with_the_card_flags_and_stores_what_was_applied() {
    let root = scratch("set");
    let folder = library(&root, &["a.png", "b.png"]);
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;

    let path = folder.join("a.png");
    let answer = m
        .act("wallpaper.set", json!({"path": path, "output": "DP-1"}))
        .await
        .unwrap();
    assert_eq!(answer.unwrap()["outputs"], json!(["DP-1"]));
    let img = fake.lines("awww img");
    assert_eq!(
        img,
        [format!(
            "awww img {} --outputs DP-1 {FLAGS}",
            path.display()
        )]
    );
    eventually(|| m.doc()["outputs"]["DP-1"]["path"] == json!(path.display().to_string())).await;
    assert_eq!(m.doc()["outputs"]["DP-2"]["path"], Value::Null);

    // Every output at once: no --outputs flag, and every output reports it.
    m.act("wallpaper.set", json!({"path": path})).await.unwrap();
    assert_eq!(fake.lines("awww img").len(), 2);
    assert!(
        fake.lines("awww img")
            .last()
            .unwrap()
            .contains(" --resize crop")
    );
    assert!(!fake.lines("awww img").last().unwrap().contains("--outputs"));
    eventually(|| m.doc()["outputs"]["DP-2"]["path"] == json!(path.display().to_string())).await;

    // The state file holds the same, so a restart can restore it.
    let saved: Value =
        serde_json::from_str(&std::fs::read_to_string(state_file(&m.dirs)).unwrap()).unwrap();
    assert_eq!(saved["all"], json!(path.display().to_string()));
}

#[tokio::test]
async fn next_prev_and_random_walk_the_library_in_order() {
    let root = scratch("walk");
    let folder = library(&root, &["a.png", "b.jpg", "c.webp"]);
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;

    let name = |v: &Option<Value>| {
        let path = v.as_ref().unwrap()["path"].as_str().unwrap().to_string();
        path.rsplit('/').next().unwrap().to_string()
    };
    let next = m.act("wallpaper.next", json!({})).await.unwrap();
    assert_eq!(name(&next), "a.png", "first from nothing");
    assert_eq!(
        name(&m.act("wallpaper.next", json!({})).await.unwrap()),
        "b.jpg"
    );
    assert_eq!(
        name(&m.act("wallpaper.next", json!({})).await.unwrap()),
        "c.webp"
    );
    assert_eq!(
        name(&m.act("wallpaper.next", json!({})).await.unwrap()),
        "a.png",
        "wraps"
    );
    assert_eq!(
        name(&m.act("wallpaper.prev", json!({})).await.unwrap()),
        "c.webp",
        "wraps back"
    );
    let random = m
        .act("wallpaper.random", json!({"output": "DP-1"}))
        .await
        .unwrap();
    assert!(random.is_some());
    assert_eq!(fake.count("awww img"), 6, "one img per step");
    assert!(
        fake.lines("awww img")
            .last()
            .unwrap()
            .contains("--outputs DP-1"),
        "a per-output step names its output"
    );
}

#[tokio::test]
async fn a_missing_backend_greys_its_choice_and_says_why() {
    let root = scratch("missing");
    let fake = Fake::new(&[]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&root)).unwrap();
    m.subscribe();
    loaded(&m).await;

    assert_eq!(
        choices_by_value(&m.choices()),
        [
            (
                "awww".into(),
                false,
                Some("mod-wallpaper.backend.missing".into())
            ),
            (
                "swww".into(),
                false,
                Some("mod-wallpaper.backend.missing".into())
            ),
        ]
    );
    let doc = m.doc();
    assert_eq!(
        doc["available"], false,
        "the quick tile is not shown for a missing backend"
    );
    assert_eq!(doc["backend"]["available"], false);
    assert_eq!(doc["backend"]["reason"], "mod-wallpaper.backend.missing");
    assert_eq!(
        fake.count("spawn"),
        0,
        "nothing is started without a binary"
    );
    let refused = m
        .act("wallpaper.set", json!({"path": root.join("x.png")}))
        .await;
    assert!(refused.is_err(), "a request without the backend is refused");
    assert_eq!(fake.count("awww img"), 0);
}

#[tokio::test]
async fn an_installed_backend_is_offered_enabled() {
    let root = scratch("choices");
    let fake = Fake::new(&["awww"]);
    let m = Mod::enable(fake, Dirs::rooted(&root), values(&root)).unwrap();
    assert_eq!(
        choices_by_value(&m.choices()),
        [
            ("awww".into(), true, None),
            (
                "swww".into(),
                false,
                Some("mod-wallpaper.backend.missing".into())
            ),
        ]
    );
}

#[tokio::test(start_paused = true)]
async fn rotation_applies_one_image_per_minute_on_a_paused_clock() {
    let root = scratch("rotate");
    let folder = library(&root, &["a.png", "b.png", "c.png"]);
    let fake = Fake::new(&["awww"]);
    fake.daemon_up
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    let img_before = fake.count("awww img");

    m.set("rotate", json!(1));
    eventually(|| m.doc()["rotation"]["on"] == true).await;
    assert!(
        m.doc()["rotation"]["next_at"].is_number(),
        "the next change is announced"
    );

    for minute in 1..=3 {
        tokio::time::advance(Duration::from_secs(60)).await;
        let want = img_before + minute;
        eventually(|| fake.count("awww img") == want).await;
    }
    assert_eq!(
        fake.count("awww img"),
        img_before + 3,
        "one img per minute, no more"
    );
    let rotated = fake.lines("awww img");
    assert!(
        rotated
            .iter()
            .all(|l| l.contains(" --transition-type fade"))
    );
}

#[tokio::test(start_paused = true)]
async fn with_rotation_off_an_idle_mod_does_no_work() {
    let root = scratch("idle");
    let folder = library(&root, &["a.png"]);
    let fake = Fake::new(&["awww"]);
    fake.daemon_up
        .store(true, std::sync::atomic::Ordering::SeqCst);
    // No subscriber: the picker is closed. The start is over when its version call has been made.
    let _m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    eventually(|| fake.count("awww --version") == 1).await;
    for _ in 0..50 {
        tokio::task::yield_now().await;
    }
    let settled = fake.calls.lock().unwrap().len();

    // Ten minutes with rotation off: no backend call, no timer.
    tokio::time::advance(Duration::from_secs(600)).await;
    for _ in 0..50 {
        tokio::task::yield_now().await;
    }
    assert_eq!(
        fake.calls.lock().unwrap().len(),
        settled,
        "no backend call, no timer, while idle"
    );
}

#[tokio::test(start_paused = true)]
async fn a_manual_set_and_a_picker_opening_do_not_move_the_per_output_timers() {
    let root = scratch("timers");
    let folder = library(&root, &["a.png", "b.png"]);
    let fake = Fake::new(&["awww"]);
    fake.daemon_up
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let mut vals = values(&folder);
    vals.insert("rotate".into(), json!(1));
    vals.insert("rotate_per_output".into(), json!(true));
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), vals).unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    assert_eq!(m.doc()["rotation"]["per_output"], true);

    // Half a minute in: a picker opens (a refresh) and DP-1 is set by hand.
    tokio::time::advance(Duration::from_secs(30)).await;
    m.subscribe();
    m.act(
        "wallpaper.set",
        json!({"path": folder.join("b.png"), "output": "DP-1"}),
    )
    .await
    .unwrap();
    let manual = fake.count("awww img");
    assert_eq!(manual, 1, "the manual set itself");

    // The minute mark: each output rotates once, on its own due time that did not move.
    tokio::time::advance(Duration::from_secs(30)).await;
    eventually(|| fake.count("awww img") == manual + 2).await;
    let rotated = fake.lines("awww img");
    assert!(rotated[1..].iter().any(|l| l.contains("--outputs DP-1")));
    assert!(rotated[1..].iter().any(|l| l.contains("--outputs DP-2")));
}

#[tokio::test(start_paused = true)]
async fn disabling_the_mod_stops_the_rotation_timer() {
    let root = scratch("disable");
    let folder = library(&root, &["a.png", "b.png"]);
    let fake = Fake::new(&["awww"]);
    fake.daemon_up
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    m.set("rotate", json!(1));
    eventually(|| m.doc()["rotation"]["on"] == true).await;
    tokio::time::advance(Duration::from_secs(60)).await;
    eventually(|| fake.count("awww img") >= 1).await;
    let once = fake.count("awww img");

    m.disable();
    for _ in 0..5 {
        tokio::time::advance(Duration::from_secs(120)).await;
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
    }
    assert_eq!(fake.count("awww img"), once, "no timer after the disable");
}

#[tokio::test]
async fn a_restart_restores_each_outputs_stored_image_without_a_transition() {
    let root = scratch("restore");
    let folder = library(&root, &["a.png", "b.png"]);
    let dirs = Dirs::rooted(&root);
    let stored = folder.join("b.png");
    std::fs::create_dir_all(dirs.state_file().parent().unwrap()).unwrap();
    std::fs::write(
        dirs.state_file(),
        json!({"all": folder.join("a.png"), "outputs": {"DP-1": {"path": stored}}}).to_string(),
    )
    .unwrap();

    // The daemon is down at enable (a restart): it is started, then the images come back.
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), dirs, values(&folder)).unwrap();
    m.subscribe();
    eventually(|| m.doc()["outputs"]["DP-2"]["path"].is_string()).await;

    assert_eq!(fake.count("spawn awww-daemon"), 1);
    let restored = fake.lines("awww img");
    assert_eq!(restored.len(), 2, "one per output");
    assert!(restored.iter().any(|l| l.contains(&format!(
        "{} --outputs DP-1 --resize crop --crop-gravity center --transition-type none",
        stored.display()
    ))));
    assert!(restored.iter().any(|l| l.contains("a.png --outputs DP-2")));
    assert_eq!(
        m.doc()["outputs"]["DP-1"]["path"],
        json!(stored.display().to_string())
    );
}

#[tokio::test(start_paused = true)]
async fn a_backend_that_stays_down_is_reported_and_a_request_says_why() {
    let root = scratch("down");
    let folder = library(&root, &["a.png"]);
    let fake = Fake::new(&["awww"]);
    fake.spawn_starts
        .store(false, std::sync::atomic::Ordering::SeqCst);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    // The start polls the daemon on the clock, so this wait lets the clock run (tokio sleeps).
    while m.doc()["loaded"] != true {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    let doc = m.doc();
    assert_eq!(doc["backend"]["available"], false);
    assert_eq!(doc["backend"]["reason"], "mod-wallpaper.backend.down");
    assert_eq!(
        doc["available"], true,
        "installed: the tile stays, with the reason"
    );
    assert_eq!(
        fake.count("spawn awww-daemon"),
        1,
        "one start attempt at enable"
    );

    let err = m
        .act(
            "wallpaper.set",
            json!({"path": folder.join("a.png"), "output": "DP-1"}),
        )
        .await
        .unwrap_err();
    assert_eq!(
        err.to_string(),
        "mod-wallpaper.backend.down",
        "the refusal names the state"
    );
    assert_eq!(
        fake.count("spawn awww-daemon"),
        1,
        "a second start inside the start gap is refused"
    );
    assert_eq!(
        fake.count("awww img"),
        0,
        "nothing reaches a backend that is down"
    );
}

#[tokio::test]
async fn refused_requests_never_reach_the_backend() {
    let root = scratch("refuse");
    let folder = library(&root, &["a.png", "notes.txt"]);
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;

    let not_image = m
        .act("wallpaper.set", json!({"path": folder.join("notes.txt")}))
        .await
        .unwrap_err();
    assert_eq!(not_image.to_string(), "mod-wallpaper.error.not_image");
    let relative = m
        .act("wallpaper.set", json!({"path": "a.png"}))
        .await
        .unwrap_err();
    assert_eq!(relative.to_string(), "mod-wallpaper.error.path");
    let unknown_output = m
        .act(
            "wallpaper.set",
            json!({"path": folder.join("a.png"), "output": "HDMI-9"}),
        )
        .await
        .unwrap_err();
    assert_eq!(
        unknown_output.to_string(),
        "mod-wallpaper.error.output_unknown"
    );
    assert_eq!(fake.count("awww img"), 0);
}

#[tokio::test]
async fn a_failed_apply_is_not_recorded_as_applied() {
    let root = scratch("failed");
    let folder = library(&root, &["a.png"]);
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;
    fake.img_fails
        .store(true, std::sync::atomic::Ordering::SeqCst);

    let err = m
        .act(
            "wallpaper.set",
            json!({"path": folder.join("a.png"), "output": "DP-1"}),
        )
        .await
        .unwrap_err();
    assert_eq!(err.to_string(), "mod-wallpaper.error.apply");
    eventually(|| m.doc()["error"]["key"] == "mod-wallpaper.error.apply").await;
    assert_eq!(
        m.doc()["outputs"]["DP-1"]["path"],
        Value::Null,
        "nothing was stored"
    );
    assert_eq!(
        m.doc()["backend"]["reason"],
        "mod-wallpaper.backend.down",
        "a failed call marks the backend down"
    );
}

#[tokio::test]
async fn favourites_toggle_and_survive_a_restart() {
    let root = scratch("favs");
    let folder = library(&root, &["a.png", "b.png"]);
    let dirs = Dirs::rooted(&root);
    let path = folder.join("a.png");
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), dirs.clone(), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;

    let on = m
        .act(
            "wallpaper.favourite",
            json!({"path": path, "scheme": "dark", "palette": "autumn-1"}),
        )
        .await
        .unwrap();
    assert_eq!(on.unwrap()["favourite"], true);
    eventually(|| {
        m.doc()["favourites"]
            .as_array()
            .is_some_and(|f| f.len() == 1)
    })
    .await;
    assert_eq!(m.doc()["favourites"][0]["scheme"], "dark");

    let bad_look = m
        .act(
            "wallpaper.favourite",
            json!({"path": folder.join("b.png"), "scheme": "sepia"}),
        )
        .await
        .unwrap_err();
    assert_eq!(bad_look.to_string(), "mod-wallpaper.error.look");
    assert_eq!(
        m.doc()["favourites"].as_array().unwrap().len(),
        1,
        "a refused look stores nothing"
    );

    // A second mod over the same state file (the daemon restarted) still has the look.
    let mut again = Mod::enable(Fake::new(&["awww"]), dirs, values(&folder)).unwrap();
    again.subscribe();
    eventually(|| {
        again.doc()["favourites"]
            .as_array()
            .is_some_and(|f| f.len() == 1)
    })
    .await;

    let off = m
        .act("wallpaper.favourite", json!({"path": path}))
        .await
        .unwrap();
    assert_eq!(off.unwrap()["favourite"], false);
}

#[tokio::test]
async fn thumbs_pages_the_library_with_palette_chips_and_marks_what_is_shown() {
    let root = scratch("thumbs");
    let folder = root.join("library");
    std::fs::create_dir_all(&folder).unwrap();
    for (i, colour) in [[200u8, 40, 40], [40, 180, 60], [40, 80, 220]]
        .iter()
        .enumerate()
    {
        let img = image::RgbImage::from_pixel(64, 48, image::Rgb(*colour));
        img.save(folder.join(format!("p{i}.png"))).unwrap();
    }
    std::fs::write(folder.join("broken.png"), b"not a png").unwrap();
    let fake = Fake::new(&["awww"]);
    fake.daemon_up
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    m.act(
        "wallpaper.set",
        json!({"path": folder.join("p1.png"), "output": "DP-1"}),
    )
    .await
    .unwrap();

    let page = m
        .act("wallpaper.thumbs", json!({"offset": 0, "limit": 2}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(page["total"], 4);
    let rows = page["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(
        rows[0]["name"], "broken.png",
        "sorted by name, case-insensitively"
    );
    assert_eq!(rows[0]["error"], "mod-wallpaper.image.unreadable");
    assert!(
        rows[0].get("thumb").is_none(),
        "a broken tile has no thumbnail"
    );
    assert_eq!(rows[1]["name"], "p0.png");
    assert!(rows[1]["thumb"].as_str().unwrap().ends_with(".jpg"));
    assert_eq!(rows[1]["palette"].as_array().unwrap().len(), 4);
    assert_eq!(rows[1]["mono"], false);

    eventually(|| m.doc()["outputs"]["DP-1"]["path"].is_string()).await;
    let shown = m
        .act("wallpaper.thumbs", json!({"query": "p1", "limit": 10}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(shown["total"], 1);
    assert_eq!(
        shown["rows"][0]["on"],
        json!(["DP-1"]),
        "the output showing it is named"
    );

    let next_page = m
        .act("wallpaper.thumbs", json!({"offset": 2, "limit": 96}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        next_page["rows"].as_array().unwrap().len(),
        2,
        "the rest of the library"
    );

    let unknown_folder = m
        .act(
            "wallpaper.thumbs",
            json!({"folder": root.join("elsewhere")}),
        )
        .await
        .unwrap_err();
    assert_eq!(
        unknown_folder.to_string(),
        "mod-wallpaper.error.folder_unknown"
    );
}

#[tokio::test]
async fn the_quick_tile_and_the_picker_share_one_document_per_subscription() {
    let root = scratch("subs");
    let folder = library(&root, &["a.png"]);
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(&root), values(&folder)).unwrap();
    m.subscribe();
    loaded(&m).await;
    let first = m.doc();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    assert_eq!(m.doc(), first, "a second subscriber gets the same state");
}
