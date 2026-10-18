//! The picker's contract through the mod's actions, against the recording fake backend (no processes):
//! a tile's request grows the transition from the tile; the theme follows the picture set with theme,
//! and a wallpaper-only change keeps it; the theme diff is a dry run of the `wallpaper` source; the
//! folder is a breadcrumb with its subfolders; a light/dark pair is badged; a favourite look stores
//! {image, scheme, variant}. Docs: docs/ux/wallpaper.md ("Design", "Beyond the basic job" 1, 2, 3).

mod common;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use common::{Fake, Mod, eventually, scratch, values};
use kurashi_mod_wallpaper::Dirs;
use serde_json::{Value, json};

fn picture(path: &Path, colour: [u8; 3]) {
    image::RgbImage::from_pixel(64, 48, image::Rgb(colour))
        .save(path)
        .unwrap();
}

/// A library with a subfolder, a light/dark pair, a teal picture and a grey (monochrome) one.
fn library_with_pictures(root: &Path) -> PathBuf {
    let folder = root.join("library");
    std::fs::create_dir_all(folder.join("sub")).unwrap();
    picture(&folder.join("teal.png"), [0x1a, 0x9e, 0x8f]);
    picture(&folder.join("wall-dark.png"), [30, 40, 60]);
    picture(&folder.join("wall-light.png"), [220, 230, 240]);
    picture(&folder.join("sub").join("red.png"), [200, 40, 40]);
    picture(&folder.join("grey.png"), [128, 128, 128]);
    folder
}

async fn picker_mod(root: &Path, folder: &Path) -> (Arc<Fake>, Mod) {
    let fake = Fake::new(&["awww"]);
    let mut m = Mod::enable(fake.clone(), Dirs::rooted(root), values(folder)).unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;
    (fake, m)
}

#[tokio::test]
async fn a_tile_grows_the_transition_from_its_position() {
    let root = scratch("grow");
    let folder = library_with_pictures(&root);
    let (fake, m) = picker_mod(&root, &folder).await;
    m.act(
        "wallpaper.set",
        json!({"path": folder.join("teal.png"), "output": "DP-1", "origin": {"x": 812, "y": 430}}),
    )
    .await
    .unwrap();
    let line = fake.lines("awww img").pop().unwrap();
    assert!(line.contains("--transition-type grow"), "{line}");
    assert!(line.contains("--transition-pos 812,430"), "{line}");
    // Without an origin the configured transition is what the backend is told.
    m.act(
        "wallpaper.set",
        json!({"path": folder.join("teal.png"), "output": "DP-1"}),
    )
    .await
    .unwrap();
    let line = fake.lines("awww img").pop().unwrap();
    assert!(line.contains("--transition-type fade"), "{line}");
    assert!(!line.contains("--transition-pos"), "{line}");
}

/// A picture the backend cannot read is refused before the backend is asked: its failure would otherwise
/// look like a backend that is down.
#[tokio::test]
async fn a_picture_that_cannot_be_read_is_refused_before_the_backend_is_asked() {
    let root = scratch("unreadable");
    let folder = library_with_pictures(&root);
    std::fs::write(folder.join("zz-broken.png"), b"not a picture").unwrap();
    let (fake, m) = picker_mod(&root, &folder).await;
    let refused = m
        .act(
            "wallpaper.set",
            json!({"path": folder.join("zz-broken.png"), "output": "DP-1"}),
        )
        .await
        .unwrap_err();
    assert_eq!(refused.to_string(), "mod-wallpaper.image.unreadable");
    assert!(
        fake.lines("awww img").is_empty(),
        "the backend was not asked"
    );
    assert_ne!(
        m.doc()["backend"]["reason"],
        "mod-wallpaper.backend.down",
        "the backend is not reported down"
    );
}

#[tokio::test]
async fn the_theme_follows_the_picture_set_with_theme_and_a_wallpaper_only_change_keeps_it() {
    let root = scratch("theme-follows");
    let folder = library_with_pictures(&root);
    let (_fake, m) = picker_mod(&root, &folder).await;
    let teal = folder.join("teal.png").display().to_string();
    assert!(
        m.doc()["theme"].get("image").is_none(),
        "no theme picture yet: the key is absent, not null (B25)"
    );

    m.act(
        "wallpaper.set",
        json!({"path": folder.join("teal.png"), "theme": true}),
    )
    .await
    .unwrap();
    eventually(|| m.doc()["theme"]["image"] == json!(teal)).await;

    m.act(
        "wallpaper.set",
        json!({"path": folder.join("sub").join("red.png"), "output": "DP-1"}),
    )
    .await
    .unwrap();
    assert_eq!(
        m.doc()["theme"]["image"],
        json!(teal),
        "a wallpaper-only change leaves the theme where it was"
    );
    let saved: Value =
        serde_json::from_str(&std::fs::read_to_string(m.dirs.state_file()).unwrap()).unwrap();
    assert_eq!(saved["theme_image"], json!(teal), "and the state keeps it");
}

#[tokio::test]
async fn the_theme_diff_is_a_dry_run_of_the_wallpaper_source() {
    let root = scratch("preview");
    let folder = library_with_pictures(&root);
    let (_fake, m) = picker_mod(&root, &folder).await;

    let teal = m
        .act(
            "wallpaper.preview",
            json!({"path": folder.join("teal.png")}),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(teal["scheme"], "dark");
    assert_eq!(teal["mono"], false);
    assert_eq!(teal["palette"], "wallpaper", "the picture's own palette");
    assert_eq!(teal["axes"], "default", "the reply says which axes it used");
    let accent = teal["roles"]["accent"].as_str().unwrap();
    assert!(accent.starts_with('#') && accent.len() == 7, "{accent}");
    assert!(teal["seed"].as_str().is_some());

    let grey = m
        .act(
            "wallpaper.preview",
            json!({"path": folder.join("grey.png"), "scheme": "light"}),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(grey["scheme"], "light");
    assert_eq!(grey["mono"], true);
    assert_eq!(
        grey["palette"], "wa-iro",
        "a monochrome picture: the palette in effect is named"
    );
    assert_eq!(grey["seed"], Value::Null);

    // A dry run: nothing is applied, nothing is stored.
    assert!(m.doc()["theme"].get("image").is_none());
    let err = m
        .act(
            "wallpaper.preview",
            json!({"path": folder.join("missing.png")}),
        )
        .await
        .unwrap_err();
    assert_eq!(err.to_string(), "mod-wallpaper.image.unreadable");
}

#[tokio::test]
async fn the_folder_is_a_breadcrumb_with_its_subfolders_and_nothing_outside_the_library() {
    let root = scratch("breadcrumb");
    let folder = library_with_pictures(&root);
    let (_fake, m) = picker_mod(&root, &folder).await;
    let sub = folder.join("sub").display().to_string();
    let top = folder.display().to_string();

    let inside = m
        .act("wallpaper.thumbs", json!({"folder": sub}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(inside["total"], 1);
    assert_eq!(inside["rows"][0]["name"], "red.png");
    assert_eq!(inside["folder"], json!(sub));
    assert_eq!(
        inside["root"],
        json!(top),
        "the breadcrumb starts at the configured folder"
    );
    assert_eq!(inside["children"], json!([]));

    let all = m
        .act("wallpaper.thumbs", json!({"folder": top}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(all["total"], 5, "the library, subfolders included");
    assert_eq!(
        all["children"],
        json!([{"path": sub, "name": "sub", "count": 1}]),
        "subfolders with pictures are offered as the next crumb"
    );

    let outside = m
        .act(
            "wallpaper.thumbs",
            json!({"folder": root.join("elsewhere").display().to_string()}),
        )
        .await
        .unwrap_err();
    assert_eq!(outside.to_string(), "mod-wallpaper.error.folder_unknown");
}

#[tokio::test]
async fn a_light_and_a_dark_picture_of_one_name_are_badged_as_a_pair() {
    let root = scratch("pairs");
    let folder = library_with_pictures(&root);
    let (_fake, m) = picker_mod(&root, &folder).await;
    let page = m
        .act("wallpaper.thumbs", json!({"query": "wall"}))
        .await
        .unwrap()
        .unwrap();
    let rows = page["rows"].as_array().unwrap();
    let dark = rows.iter().find(|r| r["name"] == "wall-dark.png").unwrap();
    assert_eq!(dark["pair"]["role"], "dark");
    assert_eq!(
        dark["pair"]["partner"],
        json!(folder.join("wall-light.png").display().to_string())
    );
    let teal = m
        .act("wallpaper.thumbs", json!({"query": "teal"}))
        .await
        .unwrap()
        .unwrap();
    assert!(
        teal["rows"][0].get("pair").is_none(),
        "a picture without a partner has no badge"
    );
}

#[tokio::test]
async fn a_favourite_look_stores_its_image_scheme_and_variant() {
    let root = scratch("looks");
    let folder = library_with_pictures(&root);
    let (_fake, m) = picker_mod(&root, &folder).await;
    let teal = folder.join("teal.png").display().to_string();

    m.act(
        "wallpaper.favourite",
        json!({"image": folder.join("teal.png"), "scheme": "light", "variant": "wallpaper"}),
    )
    .await
    .unwrap();
    eventually(|| {
        m.doc()["favourites"]
            .as_array()
            .is_some_and(|f| f.len() == 1)
    })
    .await;
    assert_eq!(
        m.doc()["favourites"][0],
        json!({"image": teal, "scheme": "light", "variant": "wallpaper"})
    );
    let looks = m
        .act("wallpaper.thumbs", json!({"favourites": true}))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(looks["total"], 1);
    assert_eq!(looks["rows"][0]["favourite"], true);

    let refused = m
        .act(
            "wallpaper.favourite",
            json!({"image": folder.join("grey.png"), "scheme": "sepia"}),
        )
        .await
        .unwrap_err();
    assert_eq!(refused.to_string(), "mod-wallpaper.error.look");
}
