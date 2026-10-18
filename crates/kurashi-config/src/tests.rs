use std::collections::BTreeMap;

use proptest::prelude::*;
use serde_json::{Value as Json, json};
use tempfile::TempDir;
use toml_edit::DocumentMut;

use crate::engine::Layers;
use crate::testing::{EDGES, FakeKey, FakeSchema, Kind};
use crate::*;

const KEYS: &[&str] = &[
    "bar.height",
    "bar.main.edge",
    "bar.main.autohide",
    "theme.palette",
    "theme.motion.speed",
    "island.enabled",
    "island.faces",
];
const OUTS: &[&str] = &["DP-1", "HDMI-A-1"];

fn open_with(dir: &TempDir, schema: FakeSchema, opts: Options) -> Config<FakeSchema> {
    Config::open(schema, Paths::rooted(dir.path()), opts)
}

fn open(dir: &TempDir) -> Config<FakeSchema> {
    open_with(dir, FakeSchema::new(), Options::default())
}

fn write(dir: &TempDir, rel: &str, text: &str) {
    let p = dir.path().join("config").join(rel);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, text).unwrap();
}

fn read_user(dir: &TempDir) -> Option<String> {
    std::fs::read_to_string(dir.path().join("config/config.toml")).ok()
}

fn val(cfg: &Config<FakeSchema>, key: &str, out: Option<&str>) -> (Json, Source) {
    let p = cfg.resolve(key, out).unwrap();
    (p.value, p.source)
}

fn slot(k: &str, o: Option<&str>) -> Slot {
    (k.to_string(), o.map(str::to_string))
}

/// Every key × (global + the outputs the strategies use).
fn snapshot(cfg: &Config<FakeSchema>) -> Vec<Option<Provenanced>> {
    let outs = [None, Some("DP-1"), Some("HDMI-A-1")];
    KEYS.iter()
        .flat_map(|k| outs.iter().map(move |o| cfg.resolve(k, *o)))
        .collect()
}

// --- resolution -----------------------------------------------------------------------------

#[test]
fn defaults_and_unknown() {
    let dir = TempDir::new().unwrap();
    let cfg = open(&dir);
    assert_eq!(val(&cfg, "bar.height", None), (json!(32), Source::Default));
    assert!(cfg.resolve("nope", None).is_none());
    assert!(cfg.diagnostics().is_empty());
    assert_eq!(cfg.rev(), 0);
}

#[test]
fn nix_layer_per_output_and_explain() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "managed.toml",
        "[bar]\nheight = 40\n\n[_managed]\nenforce = false\n",
    );
    let mut cfg = open(&dir);
    cfg.apply(&[Op::set_on("bar.height", "DP-1", json!(50))])
        .unwrap();
    assert_eq!(val(&cfg, "bar.height", None), (json!(40), Source::Nix));
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(50), Source::User)
    );
    assert_eq!(
        val(&cfg, "bar.height", Some("HDMI-A-1")),
        (json!(40), Source::Nix)
    );
    let why = cfg.explain("bar.height", Some("DP-1"));
    let got: Vec<_> = why
        .iter()
        .map(|l| (l.source.clone(), l.output.clone(), l.value.clone()))
        .collect();
    assert_eq!(
        got,
        vec![
            (Source::Default, None, json!(32)),
            (Source::Nix, None, json!(40)),
            (Source::User, Some("DP-1".into()), json!(50)),
        ]
    );
}

#[test]
fn higher_layer_global_beats_lower_layer_per_output() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "managed.toml",
        "[outputs.\"DP-1\".bar]\nheight = 60\n",
    );
    let mut cfg = open(&dir);
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(60), Source::Nix)
    );
    cfg.apply(&[Op::set("bar.height", json!(50))]).unwrap();
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(50), Source::User)
    );
}

#[test]
fn managed_enforce_is_forced_with_reason() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "managed.toml",
        "theme.palette = \"sumi\"\n[_managed]\nenforce = true\n",
    );
    let mut cfg = open(&dir);
    cfg.apply(&[Op::set("theme.palette", json!("mine"))])
        .unwrap();
    let p = cfg.resolve("theme.palette", None).unwrap();
    assert_eq!(p.value, json!("sumi"));
    assert_eq!(p.source, Source::Forced("nix".into()));
    assert_eq!(p.forced_by.as_deref(), Some("nix"));
    assert_eq!(p.reason.as_deref(), Some(REASON_NIX_ENFORCED));
    let why = cfg.explain("theme.palette", None);
    assert_eq!(
        why.last().unwrap().reason.as_deref(),
        Some(REASON_NIX_ENFORCED)
    );
    assert_eq!(why.len(), 3); // default, user, forced:nix
}

#[test]
fn forced_layer_set_and_clear_recomputes() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    let f = Forced {
        value: json!(0.0),
        forced_by: Some("compositor".into()),
        reason: Some("config.forced.no_blur".into()),
    };
    let d = cfg
        .set_forced("capability", slot("theme.motion.speed", None), f)
        .unwrap();
    assert_eq!(d.changed(), vec![slot("theme.motion.speed", None)]);
    // User changes underneath a forced value: committed, but the effective value is unchanged.
    let a = cfg
        .apply(&[Op::set("theme.motion.speed", json!(2.0))])
        .unwrap();
    assert!(a.tx_id.is_some());
    assert!(a.changed.is_empty());
    cfg.clear_forced("capability", None);
    assert_eq!(
        val(&cfg, "theme.motion.speed", None),
        (json!(2.0), Source::User)
    );
    assert!(
        cfg.set_forced(
            "capability",
            slot("theme.palette", Some("DP-1")),
            Forced {
                value: json!("x"),
                forced_by: None,
                reason: None,
            }
        )
        .is_err()
    );
}

#[test]
fn theme_layer_validated() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    let entries = BTreeMap::from([
        (slot("bar.height", None), json!(44)),
        (slot("bar.height", Some("DP-1")), json!(999)),
    ]);
    let d = cfg.set_theme_layer(Some(("ishi".into(), entries)));
    assert_eq!(d.diagnostics.len(), 1);
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(44), Source::Theme("ishi".into()))
    );
}

// --- transactions ---------------------------------------------------------------------------

#[test]
fn changed_lists_only_effective_changes() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    let a = cfg.apply(&[Op::set("theme.palette", json!("x"))]).unwrap();
    assert_eq!(a.changed, vec![slot("theme.palette", None)]);
    assert_eq!((a.rev, a.tx_id.as_deref()), (1, Some("tx-1")));
    let again = cfg.apply(&[Op::set("theme.palette", json!("x"))]).unwrap();
    assert_eq!((again.rev, again.tx_id, again.changed.len()), (1, None, 0));

    cfg.apply(&[Op::set_on("bar.height", "DP-1", json!(50))])
        .unwrap();
    let g = cfg.apply(&[Op::set("bar.height", json!(60))]).unwrap();
    assert_eq!(g.changed, vec![slot("bar.height", None)]);
    let r = cfg
        .apply(&[Op::Reset {
            key: "bar.height".into(),
            output: Some("DP-1".into()),
        }])
        .unwrap();
    assert_eq!(r.changed, vec![slot("bar.height", Some("DP-1"))]);
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(60), Source::User)
    );
}

#[test]
fn reset_prefix_and_unknown() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    cfg.apply(&[
        Op::set("theme.palette", json!("x")),
        Op::set("theme.motion.speed", json!(2.0)),
    ])
    .unwrap();
    cfg.apply(&[Op::reset("theme.motion")]).unwrap();
    assert_eq!(val(&cfg, "theme.motion.speed", None).1, Source::Default);
    assert_eq!(val(&cfg, "theme.palette", None).1, Source::User);
    cfg.apply(&[Op::reset("theme")]).unwrap();
    assert_eq!(val(&cfg, "theme.palette", None).1, Source::Default);
    let e = cfg.apply(&[Op::reset("them")]).unwrap_err();
    assert!(matches!(e[0], OpError::UnknownKey { index: 0, .. }));
}

#[test]
fn undo_stack_is_bounded() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    for i in 0..105 {
        cfg.apply(&[Op::set("bar.height", json!(20 + i))]).unwrap();
    }
    let mut n = 0;
    while cfg.undo().unwrap().is_some() {
        n += 1;
    }
    assert_eq!(n, 100);
    assert_eq!(val(&cfg, "bar.height", None), (json!(24), Source::User));
    assert_eq!(cfg.rev(), 205);
}

// --- sparse TOML ----------------------------------------------------------------------------

const COMMENTED: &str = r#"# Kurashi user config — hand edited
schema_version = 1

[bar]
height   = 36  # tall enough for kanji
main.edge = "bottom"

# per-output override
[outputs."DP-1".bar]
height = 48

[island]
faces = ["media", "clock"]
unknown_thing = 3    # unknown: must survive
enabled = "yes"      # invalid: must survive

[theme]
palette = "sumi" # wa
"#;

#[test]
fn untouched_commented_file_is_byte_identical() {
    let dir = TempDir::new().unwrap();
    write(&dir, "config.toml", COMMENTED);
    let cfg = open(&dir);
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(48), Source::User)
    );
    assert_eq!(
        val(&cfg, "bar.main.edge", None),
        (json!("bottom"), Source::User)
    );
    assert_eq!(val(&cfg, "island.faces", None).0, json!(["media", "clock"]));
    let mut keys: Vec<_> = cfg
        .diagnostics()
        .into_iter()
        .map(|d| (d.key, d.reason.i18n_key()))
        .collect();
    keys.sort();
    assert_eq!(
        keys,
        vec![
            ("island.enabled".to_string(), "config.diag.invalid"),
            (
                "island.unknown_thing".to_string(),
                "config.diag.unknown_key"
            ),
        ]
    );
    cfg.save().unwrap();
    assert_eq!(read_user(&dir).unwrap(), COMMENTED);
}

#[test]
fn writes_only_changed_keys_and_keeps_comments() {
    let dir = TempDir::new().unwrap();
    write(&dir, "config.toml", COMMENTED);
    let mut cfg = open(&dir);
    cfg.apply(&[
        Op::set("bar.height", json!(40)),
        Op::reset("theme.palette"),
        Op::set_on("island.enabled", "HDMI-A-1", json!(false)),
        Op::set("theme.motion.speed", json!(1.5)),
    ])
    .unwrap();
    let text = read_user(&dir).unwrap();
    let expected = r#"# Kurashi user config — hand edited
schema_version = 1

[bar]
height   = 40  # tall enough for kanji
main.edge = "bottom"

# per-output override
[outputs."DP-1".bar]
height = 48

[outputs.HDMI-A-1.island]
enabled = false

[island]
faces = ["media", "clock"]
unknown_thing = 3    # unknown: must survive
enabled = "yes"      # invalid: must survive

[theme.motion]
speed = 1.5
"#;
    assert_eq!(text, expected);
    // Round trip: a fresh load sees the same effective values.
    let again = open(&dir);
    assert_eq!(snapshot(&again), snapshot(&cfg));
}

#[test]
fn new_file_gets_schema_version_and_emptied_tables_vanish() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    cfg.apply(&[Op::set_on("bar.main.edge", "DP-1", json!("left"))])
        .unwrap();
    assert_eq!(
        read_user(&dir).unwrap(),
        "schema_version = 1\n\n[outputs.DP-1.bar.main]\nedge = \"left\"\n"
    );
    cfg.apply(&[Op::Reset {
        key: "bar".into(),
        output: Some("DP-1".into()),
    }])
    .unwrap();
    assert_eq!(read_user(&dir).unwrap(), "schema_version = 1\n");
}

#[test]
fn unparseable_file_is_never_overwritten() {
    let dir = TempDir::new().unwrap();
    write(&dir, "config.toml", "[bar\nheight = 3\n");
    let mut cfg = open(&dir);
    assert!(matches!(
        cfg.diagnostics()[0].reason,
        DiagnosticReason::Parse { .. }
    ));
    let e = cfg.apply(&[Op::set("bar.height", json!(40))]).unwrap_err();
    assert!(matches!(e[0], OpError::Persist { .. }));
    assert_eq!(read_user(&dir).unwrap(), "[bar\nheight = 3\n");
    assert_eq!(val(&cfg, "bar.height", None).1, Source::Default);
}

#[test]
fn reload_after_external_edit_diffs_effective_values() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    cfg.apply(&[Op::set("bar.height", json!(40))]).unwrap();
    write(
        &dir,
        "config.toml",
        "schema_version = 1\n[bar]\nheight = 40\n[theme]\npalette = \"ai\"\nbogus = 1\n",
    );
    let d = cfg.reload_user_file();
    assert_eq!(d.changed(), vec![slot("theme.palette", None)]);
    assert_eq!(d.rev, 2);
    assert_eq!(d.diagnostics.len(), 1);
    assert_eq!(cfg.diagnostics().len(), 1);
    // Undo of the earlier tx only touches its own key; the external edit survives.
    cfg.undo().unwrap().unwrap();
    assert_eq!(val(&cfg, "bar.height", None).1, Source::Default);
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("ai"), Source::User)
    );
}

// --- migrations -----------------------------------------------------------------------------

fn v1_to_v2(doc: &mut DocumentMut) -> Result<(), String> {
    // rename bar.size → bar.height, keeping the item's decor
    let bar = doc
        .get_mut("bar")
        .and_then(|b| b.as_table_like_mut())
        .ok_or("no bar")?;
    if let Some(item) = bar.remove("size") {
        bar.insert("height", item);
    }
    Ok(())
}

fn v2_to_v3(doc: &mut DocumentMut) -> Result<(), String> {
    // value change: edge "up" became "top"
    if let Some(edge) = doc
        .get_mut("bar")
        .and_then(|b| b.get_mut("main"))
        .and_then(|m| m.get_mut("edge"))
        && edge.as_str() == Some("up")
    {
        let decor = edge.as_value().unwrap().decor().clone();
        let mut v = toml_edit::Value::from("top");
        *v.decor_mut() = decor;
        *edge = toml_edit::Item::Value(v);
    }
    Ok(())
}

fn migrations() -> Vec<Migration> {
    vec![
        Migration {
            from: 2,
            to: 3,
            apply: v2_to_v3,
        },
        Migration {
            from: 1,
            to: 2,
            apply: v1_to_v2,
        },
    ]
}

#[test]
fn migrates_v1_to_v3_with_backup() {
    let dir = TempDir::new().unwrap();
    let v1 = "# mine\n[bar]\nsize = 40 # big\n\n[bar.main]\nedge = \"up\"\n";
    write(&dir, "config.toml", v1);
    let opts = Options {
        migrations: migrations(),
        ..Options::default()
    };
    let cfg = open_with(&dir, FakeSchema::with_version(3), opts.clone());
    assert!(cfg.diagnostics().is_empty(), "{:?}", cfg.diagnostics());
    assert_eq!(val(&cfg, "bar.height", None), (json!(40), Source::User));
    assert_eq!(
        val(&cfg, "bar.main.edge", None),
        (json!("top"), Source::User)
    );
    let backup = std::fs::read_to_string(dir.path().join("config/config.toml.bak-v1")).unwrap();
    assert_eq!(backup, v1);
    assert_eq!(
        read_user(&dir).unwrap(),
        "schema_version = 3\n# mine\n[bar]\nheight = 40 # big\n\n[bar.main]\nedge = \"top\"\n"
    );
    // Already current: no second backup, nothing rewritten.
    drop(cfg);
    let _ = open_with(&dir, FakeSchema::with_version(3), opts);
    assert!(!dir.path().join("config/config.toml.bak-v3").exists());
}

#[test]
fn missing_migration_loads_best_effort() {
    let dir = TempDir::new().unwrap();
    write(&dir, "config.toml", "[bar]\nsize = 40\n");
    let cfg = open_with(&dir, FakeSchema::with_version(3), Options::default());
    let reasons: Vec<_> = cfg.diagnostics().into_iter().map(|d| d.reason).collect();
    assert!(reasons.contains(&DiagnosticReason::MigrationMissing { from: 1 }));
    assert_eq!(read_user(&dir).unwrap(), "[bar]\nsize = 40\n");
}

// --- profiles -------------------------------------------------------------------------------

fn profile_setup() -> (TempDir, Config<FakeSchema>) {
    let dir = TempDir::new().unwrap();
    let bundled = dir.path().join("bundled");
    std::fs::create_dir_all(&bundled).unwrap();
    std::fs::write(
        bundled.join("kanso.toml"),
        "schema_version = 1\n[bar]\nheight = 40\n[theme]\npalette = \"sumi\"\nnope = 1\n",
    )
    .unwrap();
    let opts = Options {
        bundled_profile_dirs: vec![bundled],
        ..Options::default()
    };
    let cfg = open_with(&dir, FakeSchema::new(), opts);
    (dir, cfg)
}

#[test]
fn profile_section_load_is_one_undoable_tx() {
    let (_dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("theme.palette", json!("x")),
        Op::set("bar.height", json!(50)),
    ])
    .unwrap();
    let rev = cfg.rev();
    let d = cfg.preview_profile("kanso", Some(&["theme"])).unwrap().diff;
    assert_eq!(d.rev, rev);
    assert_eq!(d.entries.len(), 1);
    assert_eq!(d.entries[0].key, "theme.palette");
    assert_eq!(d.entries[0].before.as_ref().unwrap().source, Source::User);
    assert_eq!(
        d.entries[0].after.as_ref().unwrap().source,
        Source::Profile("kanso".into())
    );
    assert_eq!(d.diagnostics.len(), 1); // theme.nope
    assert_eq!(cfg.rev(), rev, "preview changes nothing");

    let a = cfg.load_profile("kanso", Some(&["theme"])).unwrap().applied;
    assert_eq!(a.rev, rev + 1);
    assert_eq!(a.changed, vec![slot("theme.palette", None)]);
    assert_eq!(val(&cfg, "bar.height", None), (json!(50), Source::User));
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Profile("kanso".into()))
    );
    cfg.undo().unwrap().unwrap();
    assert_eq!(val(&cfg, "theme.palette", None), (json!("x"), Source::User));
    cfg.redo().unwrap().unwrap();
    assert_eq!(val(&cfg, "theme.palette", None).0, json!("sumi"));
}

#[test]
fn full_profile_load_persists_across_restart() {
    let (dir, mut cfg) = profile_setup();
    cfg.apply(&[Op::set("bar.height", json!(50))]).unwrap();
    cfg.load_profile("kanso", None).unwrap();
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(40), Source::Profile("kanso".into()))
    );
    let again = open_with(&dir, FakeSchema::new(), Options::default());
    assert_eq!(snapshot(&again), snapshot(&cfg));
}

#[test]
fn save_profile_snapshots_non_defaults_and_shadows_bundled() {
    let (dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("bar.height", json!(50)),
        Op::set_on("bar.height", "DP-1", json!(32)),
        Op::set("island.faces", json!(["clock"])),
    ])
    .unwrap();
    cfg.set_forced(
        "capability",
        slot("theme.motion.speed", None),
        Forced {
            value: json!(0.0),
            forced_by: None,
            reason: None,
        },
    )
    .unwrap();
    let p = cfg.save_profile("kanso", Some(&["bar", "theme"])).unwrap();
    assert_eq!(
        std::fs::read_to_string(&p).unwrap(),
        "schema_version = 1\n\n[bar]\nheight = 50\n\n[outputs.DP-1.bar]\nheight = 32\n"
    );
    let list = cfg.list_profiles();
    assert_eq!(list.len(), 1);
    assert!(!list[0].2, "user profile shadows the bundled one");
    assert!(dir.path().join("config/profiles/kanso.toml").exists());
    assert!(matches!(
        cfg.save_profile("../evil", None),
        Err(ConfigError::InvalidProfileName(_))
    ));
    assert!(matches!(
        cfg.preview_profile("missing", None),
        Err(ConfigError::ProfileNotFound(_))
    ));
}

// --- per-mod profile sections (K7, K18, K22; card C-mod-sections) ---------------------------

const MOD_KEYS: &[&str] = &[
    "mods.media.seek_step",
    "mods.media.show_art",
    "mods.clock.size",
];

/// The fake schema plus two mods' settings, keyed `mods.<id>.<key>` as K22 declares them.
fn mod_schema() -> FakeSchema {
    let key = |default, kind| FakeKey {
        default,
        kind,
        per_output: false,
    };
    let mut schema = FakeSchema::new();
    schema.keys.insert(
        "mods.media.seek_step".into(),
        key(json!(5), Kind::Int { min: 1, max: 60 }),
    );
    schema
        .keys
        .insert("mods.media.show_art".into(), key(json!(true), Kind::Bool));
    schema.keys.insert(
        "mods.clock.size".into(),
        key(json!(3), Kind::Int { min: 1, max: 9 }),
    );
    schema
}

/// One bundled profile (`night`) that sets both mods.
fn mod_profile_setup() -> (TempDir, Config<FakeSchema>) {
    let dir = TempDir::new().unwrap();
    let bundled = dir.path().join("bundled");
    std::fs::create_dir_all(&bundled).unwrap();
    std::fs::write(
        bundled.join("night.toml"),
        "schema_version = 1\n[mods.media]\nseek_step = 12\nshow_art = false\n[mods.clock]\nsize = 7\n",
    )
    .unwrap();
    let opts = Options {
        bundled_profile_dirs: vec![bundled],
        ..Options::default()
    };
    let cfg = open_with(&dir, mod_schema(), opts);
    (dir, cfg)
}

fn mod_snapshot(cfg: &Config<FakeSchema>) -> Vec<Option<Provenanced>> {
    MOD_KEYS.iter().map(|k| cfg.resolve(k, None)).collect()
}

#[test]
fn section_of_a_mod_key_is_the_mod() {
    use crate::engine::section;
    assert_eq!(section("mods.media.seek_step"), "mods.media");
    assert_eq!(section("mods.media.deep.key"), "mods.media");
    assert_eq!(section("mods.media"), "mods");
    assert_eq!(section("mods..x"), "mods");
    assert_eq!(section("bar.main.edge"), "bar");
}

#[test]
fn mod_section_load_changes_only_that_mod_as_one_undoable_tx() {
    let (dir, mut cfg) = mod_profile_setup();
    cfg.apply(&[
        Op::set("mods.media.seek_step", json!(20)),
        Op::set("mods.clock.size", json!(5)),
    ])
    .unwrap();
    let rev = cfg.rev();
    let a = cfg
        .load_profile("night", Some(&["mods.media"]))
        .unwrap()
        .applied;
    assert_eq!(a.rev, rev + 1);
    let mut changed = a.changed.clone();
    changed.sort();
    assert_eq!(
        changed,
        vec![
            slot("mods.media.seek_step", None),
            slot("mods.media.show_art", None),
        ]
    );
    let night = || Source::Profile("night".into());
    assert_eq!(
        val(&cfg, "mods.media.seek_step", None),
        (json!(12), night())
    );
    assert_eq!(
        val(&cfg, "mods.media.show_art", None),
        (json!(false), night())
    );
    // Outside the section: the clock keeps its pin and receives no profile value.
    assert_eq!(val(&cfg, "mods.clock.size", None), (json!(5), Source::User));
    let reopened = open_with(&dir, mod_schema(), Options::default());
    assert_eq!(mod_snapshot(&reopened), mod_snapshot(&cfg));

    cfg.undo().unwrap().unwrap();
    assert_eq!(
        val(&cfg, "mods.media.seek_step", None),
        (json!(20), Source::User)
    );
    assert_eq!(
        val(&cfg, "mods.media.show_art", None),
        (json!(true), Source::Default)
    );
    assert_eq!(val(&cfg, "mods.clock.size", None), (json!(5), Source::User));
    cfg.redo().unwrap().unwrap();
    assert_eq!(val(&cfg, "mods.media.seek_step", None).0, json!(12));
}

#[test]
fn mods_section_loads_every_mod() {
    let (_dir, mut cfg) = mod_profile_setup();
    cfg.apply(&[
        Op::set("mods.media.seek_step", json!(20)),
        Op::set("mods.clock.size", json!(5)),
    ])
    .unwrap();
    let d = cfg.preview_profile("night", Some(&["mods"])).unwrap().diff;
    assert_eq!(d.entries.len(), 3);
    cfg.load_profile("night", Some(&["mods"])).unwrap();
    assert_eq!(
        val(&cfg, "mods.media.seek_step", None),
        (json!(12), Source::Profile("night".into()))
    );
    assert_eq!(
        val(&cfg, "mods.clock.size", None),
        (json!(7), Source::Profile("night".into()))
    );
}

#[test]
fn mod_section_filter_matches_whole_segments_only() {
    let (dir, mut cfg) = mod_profile_setup();
    cfg.apply(&[
        Op::set("mods.media.seek_step", json!(20)),
        Op::set("mods.clock.size", json!(5)),
    ])
    .unwrap();
    // `mods.med` names no section: nothing is previewed, loaded or unpinned.
    let d = cfg
        .preview_profile("night", Some(&["mods.med"]))
        .unwrap()
        .diff;
    assert!(d.entries.is_empty());
    let a = cfg
        .load_profile("night", Some(&["mods.med"]))
        .unwrap()
        .applied;
    assert_eq!(a.tx_id, None);
    assert_eq!(
        val(&cfg, "mods.media.seek_step", None),
        (json!(20), Source::User)
    );
    // Saving one mod writes only that mod's keys.
    let path = cfg.save_profile("mine", Some(&["mods.clock"])).unwrap();
    let saved = std::fs::read_to_string(path).unwrap();
    assert!(saved.contains("[mods.clock]\nsize = 5\n"), "{saved}");
    assert!(!saved.contains("seek_step"), "{saved}");
    assert!(dir.path().join("config/profiles/mine.toml").exists());
}

#[test]
fn old_layout_profile_state_loads_like_the_nested_one() {
    // Before per-mod sections every mod key sat under one `[<profile>.mods]` table. The dotted
    // keys below are the same TOML tables as the nested form, so both must load identically.
    let old = "[night.mods]\nmedia.seek_step = 12\nmedia.show_art = false\nclock.size = 7\n";
    let nested =
        "[night.mods.media]\nseek_step = 12\nshow_art = false\n\n[night.mods.clock]\nsize = 7\n";
    let open_state = |text: &str| {
        let dir = TempDir::new().unwrap();
        let state = Paths::rooted(dir.path()).profile_state_file();
        std::fs::create_dir_all(state.parent().unwrap()).unwrap();
        std::fs::write(&state, text).unwrap();
        (open_with(&dir, mod_schema(), Options::default()), dir)
    };
    let (old_cfg, _old_dir) = open_state(old);
    let (nested_cfg, _nested_dir) = open_state(nested);
    assert_eq!(mod_snapshot(&old_cfg), mod_snapshot(&nested_cfg));
    assert_eq!(
        val(&old_cfg, "mods.media.seek_step", None),
        (json!(12), Source::Profile("night".into()))
    );
    assert_eq!(
        val(&old_cfg, "mods.clock.size", None),
        (json!(7), Source::Profile("night".into()))
    );
}

// --- overlay (B13): a load changes only the keys it sets -------------------------------------

#[test]
fn a_load_keeps_the_user_changes_the_profile_does_not_set() {
    // The reported case: a user's History size survives a profile that does not name it.
    let (_dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("island.enabled", json!(false)),
        Op::set_on("island.enabled", "DP-1", json!(true)),
        Op::set("bar.main.edge", json!("bottom")),
    ])
    .unwrap();
    assert_eq!(cfg.preview_profile("kanso", None).unwrap().kept_user, 3);
    let loaded = cfg.load_profile("kanso", None).unwrap();
    assert_eq!(loaded.kept_user, 3);
    assert_eq!(
        val(&cfg, "island.enabled", None),
        (json!(false), Source::User)
    );
    assert_eq!(
        val(&cfg, "island.enabled", Some("DP-1")),
        (json!(true), Source::User)
    );
    assert_eq!(
        val(&cfg, "bar.main.edge", None),
        (json!("bottom"), Source::User)
    );
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(40), Source::Profile("kanso".into()))
    );
}

#[test]
fn a_load_replaces_a_user_value_the_profile_sets_and_the_preview_says_so() {
    let (_dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("theme.palette", json!("x")),
        Op::set("bar.main.autohide", json!(true)),
    ])
    .unwrap();
    let rev = cfg.rev();
    let review = cfg.preview_profile("kanso", None).unwrap();
    assert_eq!(cfg.rev(), rev, "preview changes nothing");
    let palette = review
        .diff
        .entries
        .iter()
        .find(|e| e.key == "theme.palette")
        .unwrap();
    assert_eq!(palette.before.as_ref().unwrap().source, Source::User);
    assert_eq!(
        palette.after.as_ref().unwrap().source,
        Source::Profile("kanso".into())
    );
    assert_eq!(review.kept_user, 1, "autohide stays, palette is replaced");

    let loaded = cfg.load_profile("kanso", None).unwrap();
    assert_eq!(loaded.kept_user, 1);
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Profile("kanso".into()))
    );
    assert_eq!(
        val(&cfg, "bar.main.autohide", None),
        (json!(true), Source::User)
    );
    // One transaction: undo brings back the replaced value and keeps the rest.
    cfg.undo().unwrap().unwrap();
    assert_eq!(val(&cfg, "theme.palette", None), (json!("x"), Source::User));
    assert_eq!(
        val(&cfg, "bar.main.autohide", None),
        (json!(true), Source::User)
    );
}

#[test]
fn a_load_replaces_every_output_override_of_a_key_it_sets() {
    let (_dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("bar.height", json!(50)),
        Op::set_on("bar.height", "DP-1", json!(32)),
    ])
    .unwrap();
    cfg.load_profile("kanso", None).unwrap();
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(40), Source::Profile("kanso".into()))
    );
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(40), Source::Profile("kanso".into()))
    );
}

#[test]
fn a_user_value_of_a_key_a_forced_layer_holds_back_stays() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "managed.toml",
        "theme.palette = \"sumi\"\n[_managed]\nenforce = true\n",
    );
    write(
        &dir,
        "profiles/mine.toml",
        "[theme]\npalette = \"kanso\"\n[bar]\nheight = 44\n",
    );
    let mut cfg = open(&dir);
    cfg.apply(&[Op::set("theme.palette", json!("x"))]).unwrap();
    let loaded = cfg.load_profile("mine", None).unwrap();
    assert_eq!(loaded.not_applied.len(), 1, "{:?}", loaded.not_applied);
    assert_eq!(loaded.kept_user, 1);
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Forced("nix".into()))
    );
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(44), Source::Profile("mine".into()))
    );
    assert!(read_user(&dir).unwrap().contains("\"x\""));
}

#[test]
fn a_section_load_keeps_the_other_keys_of_that_section() {
    let (_dir, mut cfg) = profile_setup();
    cfg.apply(&[
        Op::set("bar.main.edge", json!("bottom")),
        Op::set("bar.height", json!(50)),
    ])
    .unwrap();
    let loaded = cfg.load_profile("kanso", Some(&["bar"])).unwrap();
    assert_eq!(loaded.kept_user, 1);
    assert_eq!(
        val(&cfg, "bar.main.edge", None),
        (json!("bottom"), Source::User)
    );
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(40), Source::Profile("kanso".into()))
    );
}

#[test]
fn a_load_replaces_an_earlier_profiles_entries_only_for_the_keys_it_sets() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "profiles/a.toml",
        "[bar]\nheight = 40\n[outputs.\"DP-1\".bar]\nheight = 30\n[theme]\npalette = \"sumi\"\n",
    );
    write(&dir, "profiles/b.toml", "[bar]\nheight = 44\n");
    let mut cfg = open(&dir);
    cfg.load_profile("a", None).unwrap();
    cfg.load_profile("b", None).unwrap();
    // B sets bar.height: A's values for it go, the output one included.
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(44), Source::Profile("b".into()))
    );
    assert_eq!(
        val(&cfg, "bar.height", Some("DP-1")),
        (json!(44), Source::Profile("b".into()))
    );
    // A's palette, which B does not set, stays and keeps naming A.
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Profile("a".into()))
    );
}

// --- properties -----------------------------------------------------------------------------

fn value_for(key: &str) -> BoxedStrategy<Json> {
    match key {
        "bar.height" => (16i64..=200).prop_map(Json::from).boxed(),
        "bar.main.edge" => prop::sample::select(EDGES).prop_map(|s| json!(s)).boxed(),
        "bar.main.autohide" | "island.enabled" => any::<bool>().prop_map(Json::from).boxed(),
        "theme.palette" => "[a-z]{1,8}".prop_map(Json::from).boxed(),
        "theme.motion.speed" => (0u32..40).prop_map(|x| json!(f64::from(x) / 4.0)).boxed(),
        "island.faces" => prop::collection::vec("[a-z]{1,5}", 0..3)
            .prop_map(|v| json!(v))
            .boxed(),
        _ => unreachable!(),
    }
}

fn slot_value() -> impl Strategy<Value = (Slot, Json)> {
    (
        prop::sample::select(KEYS),
        prop::option::of(prop::sample::select(OUTS)),
    )
        .prop_flat_map(|(k, o)| {
            let o = o.filter(|_| FakeSchema::new().per_output(k));
            value_for(k).prop_map(move |v| (slot(k, o), v))
        })
}

fn layer() -> impl Strategy<Value = BTreeMap<Slot, Json>> {
    prop::collection::vec(slot_value(), 0..6).prop_map(|v| v.into_iter().collect())
}

fn layers() -> impl Strategy<Value = Layers> {
    (layer(), layer(), layer(), layer(), layer()).prop_map(|(nix, theme, profile, user, forced)| {
        Layers {
            nix,
            theme: Some(("ishi".into(), theme)),
            profile: profile
                .into_iter()
                .map(|(s, v)| (s, ("kanso".into(), v)))
                .collect(),
            user,
            forced: vec![(
                "capability".into(),
                forced
                    .into_iter()
                    .map(|(s, value)| {
                        let f = Forced {
                            value,
                            forced_by: Some("compositor".into()),
                            reason: Some("r".into()),
                        };
                        (s, f)
                    })
                    .collect(),
            )],
        }
    })
}

/// Reference model: the highest layer that has the key wins; inside a layer the output entry
/// beats the global one.
fn model(l: &Layers, key: &str, out: Option<&str>) -> (Json, Source) {
    let stack: Vec<(Source, BTreeMap<Slot, Json>)> = vec![
        (
            Source::Forced("capability".into()),
            l.forced[0]
                .1
                .iter()
                .map(|(s, f)| (s.clone(), f.value.clone()))
                .collect(),
        ),
        (Source::User, l.user.clone()),
        (
            Source::Profile("kanso".into()),
            l.profile
                .iter()
                .map(|(s, (_, v))| (s.clone(), v.clone()))
                .collect(),
        ),
        (Source::Theme("ishi".into()), l.theme.clone().unwrap().1),
        (Source::Nix, l.nix.clone()),
    ];
    for (src, m) in stack {
        let hit = out
            .and_then(|o| m.get(&slot(key, Some(o))))
            .or_else(|| m.get(&slot(key, None)));
        if let Some(v) = hit {
            return (v.clone(), src);
        }
    }
    (FakeSchema::new().default(key).unwrap(), Source::Default)
}

fn valid_op() -> impl Strategy<Value = Op> {
    let reset_keys: Vec<&str> = KEYS
        .iter()
        .copied()
        .chain(["bar", "bar.main", "theme", "island"])
        .collect();
    prop_oneof![
        3 => slot_value().prop_map(|((key, output), value)| Op::Set { key, output, value }),
        1 => (
            prop::sample::select(reset_keys),
            prop::option::of(prop::sample::select(OUTS)),
        )
            .prop_map(|(k, o)| Op::Reset {
                key: k.into(),
                output: o.map(str::to_string),
            }),
    ]
}

fn invalid_op() -> impl Strategy<Value = Op> {
    prop_oneof![
        Just(Op::set("nope.key", json!(1))),
        (201i64..1000).prop_map(|h| Op::set("bar.height", json!(h))),
        Just(Op::set_on("theme.palette", "DP-1", json!("x"))),
        Just(Op::set("bar.main.edge", json!("diagonal"))),
        Just(Op::set("island.enabled", Json::Null)),
        Just(Op::set("island.faces", json!([1, 2]))),
        Just(Op::reset("nope")),
    ]
}

/// Config with random non-transactional layers and a user layer built through `apply`.
fn seeded(dir: &TempDir, l: &Layers, seed_ops: &[Op]) -> Config<FakeSchema> {
    let mut cfg = open(dir);
    cfg.layers.nix = l.nix.clone();
    cfg.layers.theme = l.theme.clone();
    cfg.layers.forced = l.forced.clone();
    cfg.apply(seed_ops).unwrap();
    cfg
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    /// (a) The effective value equals the highest layer that has the key.
    #[test]
    fn prop_precedence(l in layers()) {
        let dir = TempDir::new().unwrap();
        let mut cfg = open(&dir);
        cfg.layers = l.clone();
        for k in KEYS {
            for o in [None, Some("DP-1"), Some("HDMI-A-1")] {
                prop_assert_eq!(val(&cfg, k, o), model(&l, k, o), "{} {:?}", k, o);
            }
        }
    }

    /// (b) Removing the user value yields the next layer's value (never sticks).
    #[test]
    fn prop_reset_falls_through(l in layers(), (s, v) in slot_value()) {
        let dir = TempDir::new().unwrap();
        let mut cfg = open(&dir);
        let mut l = l;
        let key = s.0.clone();
        l.user.insert((key.clone(), None), v);
        cfg.layers = l.clone();
        cfg.apply(&[Op::Reset { key: key.clone(), output: None }]).unwrap();
        l.user.remove(&(key.clone(), None));
        for o in [None, Some("DP-1"), Some("HDMI-A-1")] {
            prop_assert_eq!(val(&cfg, &key, o), model(&l, &key, o));
        }
        prop_assert_ne!(val(&cfg, &key, None).1, Source::User);
    }

    /// (c) undo(apply(ops)) restores every effective value, redo re-applies, and the file on
    /// disk always reloads to the in-memory state.
    #[test]
    fn prop_undo_redo(
        l in layers(),
        seed in prop::collection::vec(valid_op(), 0..6),
        ops in prop::collection::vec(valid_op(), 1..8),
    ) {
        let dir = TempDir::new().unwrap();
        let mut cfg = seeded(&dir, &l, &seed);
        let before = snapshot(&cfg);
        let applied = cfg.apply(&ops).unwrap();
        let after = snapshot(&cfg);
        if applied.tx_id.is_some() {
            cfg.undo().unwrap().unwrap();
        }
        prop_assert_eq!(snapshot(&cfg), before);
        if applied.tx_id.is_some() {
            cfg.redo().unwrap().unwrap();
        }
        prop_assert_eq!(snapshot(&cfg), after.clone());
        let reopened = seeded(&dir, &l, &[]);
        prop_assert_eq!(snapshot(&reopened), after);
    }

    /// (d) A batch with one invalid op changes nothing (memory, revision, file, undo stack).
    #[test]
    fn prop_invalid_batch_is_atomic(
        l in layers(),
        seed in prop::collection::vec(valid_op(), 0..6),
        mut ops in prop::collection::vec(valid_op(), 0..8),
        bad in invalid_op(),
        at in any::<prop::sample::Index>(),
    ) {
        let dir = TempDir::new().unwrap();
        let mut cfg = seeded(&dir, &l, &seed);
        let (snap, rev, file, undo) = (snapshot(&cfg), cfg.rev(), read_user(&dir), cfg.can_undo());
        let idx = at.index(ops.len() + 1);
        ops.insert(idx, bad);
        let errs = cfg.apply(&ops).unwrap_err();
        prop_assert_eq!(errs.len(), 1);
        let index = match &errs[0] {
            OpError::UnknownKey { index, .. }
            | OpError::NotPerOutput { index, .. }
            | OpError::Invalid { index, .. } => *index,
            OpError::Persist { .. } => usize::MAX,
        };
        prop_assert_eq!(index, idx);
        prop_assert_eq!(snapshot(&cfg), snap);
        prop_assert_eq!(cfg.rev(), rev);
        prop_assert_eq!(read_user(&dir), file);
        prop_assert_eq!(cfg.can_undo(), undo);
    }
}

// --- profile files: export, import review, held entries (I35) -----------------------------------

#[test]
fn export_leaves_out_per_output_and_places_then_import_reviews_first() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "profiles/mine.toml",
        "schema_version = 1\n[bar]\nheight = 40\n[theme]\npalette = \"sumi\"\n\
         [island]\nfaces = [\"~/faces\", \"clock\"]\n[outputs.\"DP-1\".bar]\nheight = 50\n",
    );
    let cfg = open(&dir);
    let out = dir.path().join("export").join("mine.toml");
    let exported = cfg.export_profile("mine", &out).unwrap();
    assert_eq!(exported.path, out);
    let mut left: Vec<Skipped> = exported.left_out;
    left.sort_by(|a, b| a.key.cmp(&b.key));
    assert_eq!(
        left,
        vec![
            Skipped {
                key: "bar.height".into(),
                output: Some("DP-1".into()),
                reason: REASON_EXPORT_PER_OUTPUT.into(),
                forced_by: None,
            },
            Skipped {
                key: "island.faces".into(),
                output: None,
                reason: REASON_EXPORT_PATH.into(),
                forced_by: None,
            },
        ]
    );
    let text = std::fs::read_to_string(&out).unwrap();
    assert!(
        text.contains("height = 40") && text.contains("palette = \"sumi\""),
        "{text}"
    );
    assert!(!text.contains("DP-1") && !text.contains("faces"), "{text}");

    // Another machine: the review changes nothing; the load is one undoable transaction.
    let other = TempDir::new().unwrap();
    let mut cfg = open(&other);
    let rev = cfg.rev();
    let review = cfg.review_profile_file(&out, None).unwrap();
    assert_eq!(cfg.rev(), rev, "review changes nothing");
    assert!(review.diff.entries.iter().any(|e| e.key == "theme.palette"));
    assert!(review.not_applied.is_empty());
    let loaded = cfg.load_profile_file(&out, None).unwrap();
    assert_eq!(loaded.applied.rev, rev + 1);
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Profile("mine".into()))
    );
    cfg.undo().unwrap().unwrap();
    assert_eq!(val(&cfg, "theme.palette", None).1, Source::Default);
}

#[test]
fn profile_entries_a_forced_layer_holds_back_are_reported_not_applied() {
    let dir = TempDir::new().unwrap();
    write(
        &dir,
        "managed.toml",
        "theme.palette = \"sumi\"\n[_managed]\nenforce = true\n",
    );
    write(
        &dir,
        "profiles/mine.toml",
        "[theme]\npalette = \"kanso\"\n[bar]\nheight = 44\n",
    );
    let mut cfg = open(&dir);
    let review = cfg.preview_profile("mine", None).unwrap();
    let held = Skipped {
        key: "theme.palette".into(),
        output: None,
        reason: REASON_NIX_ENFORCED.into(),
        forced_by: Some("nix".into()),
    };
    assert_eq!(review.not_applied, vec![held]);
    let loaded = cfg.load_profile("mine", None).unwrap();
    assert_eq!(loaded.not_applied, review.not_applied);
    assert_eq!(
        val(&cfg, "theme.palette", None),
        (json!("sumi"), Source::Forced("nix".into()))
    );
    assert_eq!(
        val(&cfg, "bar.height", None),
        (json!(44), Source::Profile("mine".into()))
    );
}

#[test]
fn profile_file_refusals_name_the_problem() {
    let dir = TempDir::new().unwrap();
    let mut cfg = open(&dir);
    let missing = dir.path().join("nope.toml");
    assert!(matches!(
        cfg.review_profile_file(&missing, None),
        Err(ConfigError::Unreadable(_))
    ));
    let bad = dir.path().join(".hidden.toml");
    std::fs::write(&bad, "[bar]\nheight = 40\n").unwrap();
    assert!(matches!(
        cfg.load_profile_file(&bad, None),
        Err(ConfigError::InvalidProfileName(_))
    ));
}
