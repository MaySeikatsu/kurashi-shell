//! Schema v8 (session 35, W92 row 2): the desk's weather card is the weather mod's own; `v7_to_v8` keeps what a file
//! showed — the card's place in the columns, and that it was switched off.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{Options, Paths};
use kurashid::Hub;
use kurashid::config::ConfigStore;

/// The file after the store opened (and migrated) it.
fn migrated(src: &str) -> toml::Table {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root: PathBuf =
        std::env::temp_dir().join(format!("kurashid-mig8-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("config")).unwrap();
    let paths = Paths::rooted(&root);
    std::fs::write(paths.user_file(), src).unwrap();
    let _store = ConfigStore::open(
        Hub::new(),
        kurashi_schema::v1::registry(),
        Paths::rooted(&root),
        Options::default(),
    );
    let out = std::fs::read_to_string(paths.user_file()).unwrap();
    let _ = std::fs::remove_dir_all(&root);
    out.parse().unwrap_or_else(|e| panic!("{e}: {out}"))
}

fn strings(v: &toml::Value) -> Vec<&str> {
    v.as_array()
        .unwrap()
        .iter()
        .filter_map(toml::Value::as_str)
        .collect()
}

#[test]
fn the_weather_card_keeps_its_place_under_the_mods_id() {
    let doc = migrated(
        "schema_version = 7\n\n[desktop]\nenabled = true\nright = [\"weather\", \"clock\"]\nleft = [\"calendar\"]\n",
    );
    assert_eq!(
        doc["schema_version"].as_integer(),
        Some(i64::from(kurashi_schema::v1::VERSION))
    );
    let desk = &doc["desktop"];
    assert_eq!(strings(&desk["right"]), ["mod:weather:weather", "clock"]);
    assert_eq!(strings(&desk["left"]), ["calendar"]);
    assert!(desk.get("hidden").is_none() && desk.get("weather").is_none());
}

#[test]
fn a_weather_card_that_was_off_is_hidden_and_the_switch_is_gone() {
    let doc = migrated(
        "schema_version = 7\n\n[desktop]\nweather = false\nhidden = [\"mod:tasks:notes\"]\n\n[outputs.\"DP-1\".desktop]\nweather = false\n",
    );
    let desk = &doc["desktop"];
    assert!(desk.get("weather").is_none(), "{doc}");
    assert_eq!(
        strings(&desk["hidden"]),
        ["mod:tasks:notes", "mod:weather:weather"]
    );
    let out = &doc["outputs"]["DP-1"]["desktop"];
    assert!(out.get("weather").is_none());
    assert_eq!(strings(&out["hidden"]), ["mod:weather:weather"]);
}

#[test]
fn a_weather_card_that_was_on_leaves_nothing_behind() {
    let doc = migrated("schema_version = 7\n\n[desktop]\nweather = true\nmedia = false\n");
    let desk = &doc["desktop"];
    assert!(desk.get("weather").is_none() && desk.get("hidden").is_none());
    assert_eq!(desk["media"].as_bool(), Some(false));
}
