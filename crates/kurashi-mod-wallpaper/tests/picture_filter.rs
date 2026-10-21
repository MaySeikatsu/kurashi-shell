//! K59: the host's picture filter. Each output is shown the filter's file for its size (the texture baked in) while
//! the state keeps the picture's own path; a change of the filter shows every picture again, with a fade.

mod common;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use common::{Mod, eventually, scratch, values};
use kurashi_mod_api::PictureFilter;
use kurashi_mod_wallpaper::Dirs;
use serde_json::json;
use tokio::sync::watch;

/// Bakes only for outputs 2560 px wide, into `<picture>.baked-<w>x<h>.png` (no file is written: the fake backend
/// never reads it).
struct WideOnly(watch::Sender<u64>);

impl PictureFilter for WideOnly {
    fn filter(&self, picture: &Path, size: (u32, u32), _scale: f32) -> PathBuf {
        if size.0 == 2560 {
            PathBuf::from(format!(
                "{}.baked-{}x{}.png",
                picture.display(),
                size.0,
                size.1
            ))
        } else {
            picture.to_path_buf()
        }
    }

    fn changes(&self) -> watch::Receiver<u64> {
        self.0.subscribe()
    }
}

#[tokio::test]
async fn each_output_is_shown_its_filtered_picture_and_a_change_reapplies() {
    let root = scratch("filter");
    let folder = root.join("library");
    std::fs::create_dir_all(&folder).unwrap();
    let pic = folder.join("teal.png");
    image::RgbImage::from_pixel(64, 48, image::Rgb([0x1a, 0x9e, 0x8f]))
        .save(&pic)
        .unwrap();
    let fake = common::Fake::new(&["awww"]);
    let filter = Arc::new(WideOnly(watch::channel(0).0));
    let mut m = Mod::enable_filtered(
        fake.clone(),
        Dirs::rooted(&root),
        values(&folder),
        Some(filter.clone()),
    )
    .unwrap();
    m.subscribe();
    eventually(|| m.doc()["loaded"] == true).await;

    m.act("wallpaper.set", json!({"path": pic})).await.unwrap();
    let lines = fake.lines("awww img");
    let baked = format!("{}.baked-2560x1440.png", pic.display());
    assert!(
        lines
            .iter()
            .any(|l| l.contains(&baked) && l.contains("DP-1")),
        "{lines:?}"
    );
    assert!(
        lines.iter().any(
            |l| l.contains(&format!("{} ", pic.display())) && l.contains("DP-2")
                || l.ends_with(&pic.display().to_string()) && l.contains("DP-2")
        ),
        "{lines:?}"
    );
    // The document and the state keep the picture's own path.
    assert!(!m.doc().to_string().contains(".baked-"), "{}", m.doc());

    let before = fake.count("awww img");
    filter.0.send_modify(|v| *v += 1);
    eventually(|| fake.count("awww img") >= before + 2).await;
    let again = fake.lines("awww img");
    assert!(
        again[before..].iter().all(|l| l.contains("fade")),
        "{again:?}"
    );
    let _ = std::fs::remove_dir_all(&root);
}
