//! The `records` setting type in the daemon (K38, MODS.md "Records", CONTRACT 89): a mod's list of rows
//! is a config key like any other. A set is checked field by field and stored as given; every read shows
//! every declared field, whichever layer the row came from; a rejection names the row and the field; a
//! list pinned by Nix is forced and masks the user's own. Drives `ConfigStore` directly, as
//! mod_settings.rs does, with the test mod `tests/data/mods/records`.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use kurashi_config::{FORCED_NIX, Options, Paths, REASON_NIX_ENFORCED, Source};
use kurashi_ipc::{ApplyOp, OpError};
use kurashi_mods::Registry;
use kurashid::Hub;
use kurashid::config::ConfigStore;
use semver::Version;
use serde_json::{Value, json};

const PINS: &str = "mods.records.pins";

/// The test mods (`tests/data/mods`): `records`, this file's, and `hello`.
fn discover() -> Registry {
    let version = Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/data/mods");
    Registry::discover(&[dir], &version)
}

struct Fixture {
    store: Arc<ConfigStore>,
    hub: Arc<Hub>,
    reg: Registry,
    root: PathBuf,
}

/// A store over a fresh config dir. `user_toml` is the user's file from an earlier session, `managed`
/// the Nix layer; the `records` mod is discovered and turned on.
fn open(user_toml: Option<&str>, managed: Option<&str>) -> Fixture {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-records-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let paths = Paths::rooted(&root);
    std::fs::create_dir_all(&paths.config_dir).unwrap();
    if let Some(text) = user_toml {
        std::fs::write(paths.user_file(), text).unwrap();
    }
    if let Some(text) = managed {
        std::fs::write(paths.managed_file(), text).unwrap();
    }
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        paths,
        Options::default(),
    );
    let mut reg = discover();
    reg.enable("records").unwrap();
    store.sync_mods(&reg);
    Fixture {
        store,
        hub,
        reg,
        root,
    }
}

fn set(f: &Fixture, value: Value) -> Result<(), Vec<OpError>> {
    f.store
        .apply(&[ApplyOp::Set {
            set: PINS.into(),
            value,
            output: None,
        }])
        .map(|_| ())
}

fn pin(id: &str, target: &str) -> Value {
    json!({"id": id, "title": id, "target": target})
}

#[test]
fn the_settings_page_describes_the_list_and_its_fields() {
    let f = open(None, None);
    let (_, doc) = f.hub.snapshot("schema.settings").unwrap();
    let page = doc["pages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == "mods.records")
        .expect("a loaded mod has a page");
    let row = page["sections"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|s| s["rows"].as_array().unwrap().iter())
        .find(|r| r["key"] == PINS)
        .expect("the list is on the page");
    assert_eq!(row["control"], "records");
    assert_eq!(row["default"], json!([]));
    assert_eq!(row["record"]["item_label"], "title");
    assert_eq!(row["record"]["unique"], "id");
    let fields: Vec<&str> = row["record"]["fields"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["key"].as_str().unwrap())
        .collect();
    assert_eq!(fields, ["id", "title", "target", "view", "keep", "size"]);
}

#[test]
fn a_list_is_stored_checked_and_read_back_with_every_field() {
    let f = open(None, None);
    let rows = json!([
        pin("home", "https://example.org"),
        {"id": "docs", "title": "Docs", "target": "mod:webdock:docs", "view": "mobile"}
    ]);
    set(&f, rows).unwrap();
    let p = f.store.get(PINS, None).unwrap();
    assert_eq!(p.source, Source::User);
    assert_eq!(p.reason, None);
    // Every declared field is present; the absent optional ones took their defaults.
    assert_eq!(
        p.value,
        json!([
            {"id": "home", "title": "home", "target": "https://example.org", "view": "default", "keep": false, "size": 3},
            {"id": "docs", "title": "Docs", "target": "mod:webdock:docs", "view": "mobile", "keep": false, "size": 3}
        ])
    );
    // The document carries the same provenance as cfg.get (K21).
    let doc = f.store.document();
    assert_eq!(doc["values"][PINS], json!(&p));
}

#[test]
fn a_bad_row_is_refused_at_its_field_and_the_list_stays_as_it_was() {
    let f = open(None, None);
    set(&f, json!([pin("home", "https://example.org")])).unwrap();
    let before = f.store.get(PINS, None).unwrap().value;
    let cases: [(Value, &str, &str); 10] = [
        (
            json!([pin("home", "https://a"), pin("docs", "ftp://x")]),
            "mods.records.pins[1].target",
            "error.config.record_scheme",
        ),
        (
            json!([pin("Home", "https://a")]),
            "mods.records.pins[0].id",
            "error.config.record_slug",
        ),
        (
            json!([pin("a", "https://a"), pin("a", "https://b")]),
            "mods.records.pins[1].id",
            "error.config.record_duplicate",
        ),
        (
            json!([{"id": "a", "title": "a", "target": "https://a", "color": "red"}]),
            "mods.records.pins[0].color",
            "error.config.record_unknown_field",
        ),
        (
            json!([{"id": "a", "target": "https://a"}]),
            "mods.records.pins[0].title",
            "error.config.record_missing_field",
        ),
        (
            json!([{"id": "a", "title": "a", "target": "https://a", "size": 10}]),
            "mods.records.pins[0].size",
            "error.config.record_out_of_range",
        ),
        (
            json!([{"id": "a", "title": "a", "target": "https://a", "view": "tv"}]),
            "mods.records.pins[0].view",
            "error.config.record_choice",
        ),
        (
            json!([{"id": "a", "title": "a", "target": "https://a", "keep": "yes"}]),
            "mods.records.pins[0].keep",
            "error.config.record_wrong_type",
        ),
        (
            json!([1]),
            "mods.records.pins[0]",
            "error.config.record_not_a_record",
        ),
        (json!("not a list"), PINS, "error.config.wrong_type"),
    ];
    for (rows, path, code) in cases {
        let errs = set(&f, rows.clone()).expect_err(&format!("refused: {rows}"));
        assert_eq!(
            (errs[0].key.as_deref(), errs[0].code.as_str()),
            (Some(path), code),
            "for {rows}"
        );
    }
    assert_eq!(f.store.get(PINS, None).unwrap().value, before);
}

#[test]
fn undo_brings_the_previous_list_back() {
    let f = open(None, None);
    set(&f, json!([pin("a", "https://a")])).unwrap();
    set(&f, json!([pin("b", "https://b")])).unwrap();
    f.store.undo(false).unwrap();
    assert_eq!(f.store.get(PINS, None).unwrap().value[0]["id"], "a");
}

#[test]
fn the_list_is_written_to_the_user_file_and_loads_back_the_same() {
    let f = open(None, None);
    set(
        &f,
        json!([
            pin("home", "https://example.org"),
            pin("docs", "mod:webdock:docs")
        ]),
    )
    .unwrap();
    let text = std::fs::read_to_string(Paths::rooted(&f.root).user_file()).unwrap();
    let parsed: toml::Table = toml::from_str(&text).expect("the user file is TOML");
    assert_eq!(
        parsed["mods"]["records"]["pins"].as_array().unwrap().len(),
        2
    );
    // A new daemon on the same files reads the same list back.
    let hub = Hub::new();
    let again = ConfigStore::open(
        hub,
        kurashi_schema::v1::registry(),
        Paths::rooted(&f.root),
        Options::default(),
    );
    again.sync_mods(&f.reg);
    assert_eq!(
        again.get(PINS, None).unwrap().value,
        f.store.get(PINS, None).unwrap().value
    );
}

#[test]
fn a_list_pinned_by_nix_is_forced_and_masks_the_users_list() {
    let managed = "mods.records.pins = [{ id = \"nix\", title = \"From Nix\", target = \"https://nix.example\" }]\n\n[_managed]\nenforce = true\n";
    let f = open(None, Some(managed));
    let want = json!([{
        "id": "nix",
        "title": "From Nix",
        "target": "https://nix.example",
        "view": "default",
        "keep": false,
        "size": 3
    }]);
    let p = f.store.get(PINS, None).unwrap();
    assert_eq!(p.value, want);
    assert_eq!(p.source, Source::Forced(FORCED_NIX.into()));
    assert_eq!(p.forced_by.as_deref(), Some(FORCED_NIX));
    assert_eq!(p.reason.as_deref(), Some(REASON_NIX_ENFORCED));
    // The user's own list does not take effect: accepted or refused, the pinned one stays.
    let _ = set(&f, json!([pin("mine", "https://mine.example")]));
    let after = f.store.get(PINS, None).unwrap();
    assert_eq!(after.value, want);
    assert_eq!(after.source, Source::Forced(FORCED_NIX.into()));
}

#[test]
fn a_switched_off_mod_keeps_its_list_as_configured() {
    let mut f = open(None, None);
    set(&f, json!([pin("a", "https://a")])).unwrap();
    f.reg.disable("records").unwrap();
    f.store.sync_mods(&f.reg);
    let p = f.store.get(PINS, None).unwrap();
    assert_eq!(p.reason.as_deref(), Some("mods.disabled"));
    assert_eq!(p.value[0]["id"], "a");
}
