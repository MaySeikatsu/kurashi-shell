//! Profile export and import, the not-applied review, `settings.open` and the island face labels
//! (I25, I35, I37), through the daemon's actions. Every root is a temp directory; the Settings
//! window is a fake `qs` script on a temp PATH, never a real window.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_config::{Options, Paths, Source};
use kurashi_ipc::ApplyOp;
use kurashi_island::IslandConfig;
use kurashid::config::{ConfigStore, SettingsApp};
use kurashid::island::IslandHost;
use kurashid::{ActionError, ActionRegistry, Hub};
use serde_json::{Value, json};

/// The island faces `main.rs` registers as core (the transients among them are not offered).
const CORE_FACES: [&str; 7] = [
    "clock",
    "media",
    "notifications",
    "volume",
    "brightness",
    "power",
    "bluetooth",
];

fn root(tag: &str) -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!(
        "kurashid-settings-{tag}-{}-{n}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

/// `root/config/<rel>`, written before the daemon opens its config.
fn write_config(root: &Path, rel: &str, text: &str) {
    let p = root.join("config").join(rel);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, text).unwrap();
}

struct Fx {
    store: Arc<ConfigStore>,
    actions: ActionRegistry,
    hub: Arc<Hub>,
}

fn open(root: &Path, app: SettingsApp) -> Fx {
    let hub = Hub::new();
    let store = ConfigStore::open(
        hub.clone(),
        kurashi_schema::v1::registry(),
        Paths::rooted(root),
        Options::default(),
    );
    let mut actions = ActionRegistry::default();
    store.register_actions_with(&mut actions, app);
    Fx {
        store,
        actions,
        hub,
    }
}

impl Fx {
    async fn call(&self, action: &str, args: Value) -> Result<Value, ActionError> {
        self.actions
            .invoke(action, args)
            .await
            .map(|d| d.unwrap_or(Value::Null))
    }

    fn set(&self, key: &str, value: Value, output: Option<&str>) {
        self.store
            .apply(&[ApplyOp::Set {
                set: key.into(),
                value,
                output: output.map(String::from),
            }])
            .unwrap();
    }
}

/// `(key, output)` of every `left_out` / `not_applied` entry, sorted.
fn keys_of(list: &Value) -> Vec<(String, Option<String>)> {
    let mut keys: Vec<(String, Option<String>)> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            (
                e["key"].as_str().unwrap().to_string(),
                e["output"].as_str().map(String::from),
            )
        })
        .collect();
    keys.sort();
    keys
}

fn unset_app() -> SettingsApp {
    SettingsApp {
        dir: PathBuf::from("/nonexistent/kurashi-settings"),
        path: Default::default(),
    }
}

#[tokio::test]
async fn export_then_import_round_trip_drops_machine_local_keys() {
    let here = root("export");
    let fx = open(&here, unset_app());
    // This machine's look: a per-output bar, a palette, and a terminal command that names a place.
    fx.set("bar.height", json!(36), None);
    fx.set("bar.height", json!(40), Some("DP-1"));
    fx.set("theme.colors.palette", json!("kanso"), None);
    fx.set("launcher.terminal", json!(["/usr/bin/foot", "-e"]), None);
    fx.call("profile.save", json!({"name": "mine"}))
        .await
        .unwrap();

    let file = here.join("share").join("mine.toml");
    let exported = fx
        .call(
            "profile.export",
            json!({"name": "mine", "path": file.to_str().unwrap()}),
        )
        .await
        .unwrap();
    assert_eq!(
        keys_of(&exported["left_out"]),
        vec![
            ("bar.height".into(), Some("DP-1".into())),
            ("launcher.terminal".into(), None),
        ]
    );
    assert!(
        exported["left_out"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["reason"] == "config.export.path")
    );
    let text = std::fs::read_to_string(&file).unwrap();
    assert!(text.contains("palette = \"kanso\""), "{text}");
    assert!(text.contains("height = 36"), "{text}");
    assert!(!text.contains("DP-1") && !text.contains("foot"), "{text}");

    // Row 101 (I64 (1)): on this machine "mine" is a saved profile, so a file named mine.toml is refused — its
    // values would carry the saved profile's name — in the review and in the apply, before anything is read.
    for args in [
        json!({"path": file.to_str().unwrap()}),
        json!({"path": file.to_str().unwrap(), "apply": true}),
    ] {
        assert_eq!(
            fx.call("profile.import", args).await.unwrap_err(),
            ActionError::Invalid("config.error.profile_name_taken".into())
        );
    }

    // Another machine: the review changes nothing, then one transaction applies it.
    let there = root("import");
    let other = open(&there, unset_app());
    let rev = other.store.document()["history"]["can_undo"].clone();
    let path = file.to_str().unwrap();
    let review = other
        .call("profile.import", json!({"path": path}))
        .await
        .unwrap();
    assert_eq!(review["name"], "mine");
    assert!(
        review["diff"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["key"] == "theme.colors.palette")
    );
    assert_eq!(review["not_applied"], json!([]));
    assert_eq!(review["diagnostics"], json!([]));
    assert_eq!(other.store.document()["history"]["can_undo"], rev);
    assert!(
        other
            .store
            .get("theme.colors.palette", None)
            .unwrap()
            .source
            // A review applies nothing: the default style's palette still (K53).
            == Source::Theme("style:washi".into())
    );

    let applied = other
        .call("profile.import", json!({"path": path, "apply": true}))
        .await
        .unwrap();
    assert!(applied["rev"].as_u64().is_some(), "{applied}");
    let palette = other.store.get("theme.colors.palette", None).unwrap();
    assert_eq!(palette.value, json!("kanso"));
    assert_eq!(palette.source, Source::Profile("mine".into()));
    let _ = std::fs::remove_dir_all(&here);
    let _ = std::fs::remove_dir_all(&there);
}

#[tokio::test]
async fn import_refuses_relative_and_unreadable_paths() {
    let dir = root("refuse");
    let fx = open(&dir, unset_app());
    let err = fx
        .call("profile.import", json!({"path": "mine.toml"}))
        .await
        .unwrap_err();
    assert_eq!(
        err,
        ActionError::Invalid("config.error.profile_path".into())
    );
    let missing = dir.join("missing.toml");
    let err = fx
        .call("profile.import", json!({"path": missing.to_str().unwrap()}))
        .await
        .unwrap_err();
    assert_eq!(
        err,
        ActionError::Invalid("config.error.profile_unreadable".into())
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn preview_lists_a_nix_forced_key_as_not_applied() {
    let dir = root("forced");
    write_config(
        &dir,
        "managed.toml",
        "[bar]\nheight = 48\n[_managed]\nenforce = true\n",
    );
    write_config(
        &dir,
        "profiles/nixy.toml",
        "[bar]\nheight = 40\n[theme.colors]\npalette = \"kanso\"\n",
    );
    let fx = open(&dir, unset_app());
    let preview = fx
        .call("profile.preview", json!({"name": "nixy"}))
        .await
        .unwrap();
    assert_eq!(
        keys_of(&preview["not_applied"]),
        vec![("bar.height".into(), None)]
    );
    assert_eq!(
        preview["not_applied"][0]["reason"],
        "config.forced.nix_enforced"
    );
    assert_eq!(preview["not_applied"][0]["forced_by"], "nix");
    assert!(
        preview["diff"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["key"] == "theme.colors.palette"),
        "{preview}"
    );
    let loaded = fx
        .call("profile.load", json!({"name": "nixy"}))
        .await
        .unwrap();
    assert_eq!(
        keys_of(&loaded["not_applied"]),
        vec![("bar.height".into(), None)]
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// A fake `qs`: `ipc` succeeds only while `running` exists in its directory (a window runs), and
/// records its call in `ipc`; a launch records `KURASHI_SETTINGS_KEY` in `launched` and
/// `KURASHI_SETTINGS_PAGE` in `launched-page`.
fn fake_qs(root: &Path) -> (PathBuf, PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    let settings = root.join("settings");
    std::fs::create_dir_all(&settings).unwrap();
    std::fs::write(settings.join("shell.qml"), "").unwrap();
    let bin = root.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let qs = bin.join("qs");
    std::fs::write(
        &qs,
        "#!/bin/sh\n\
         if [ \"$3\" = \"ipc\" ]; then\n\
           [ -e \"$(dirname \"$0\")/running\" ] || exit 1\n\
           printf '%s' \"$6 $7\" > \"$(dirname \"$0\")/ipc\"\n\
           exit 0\n\
         fi\n\
         printf '%s' \"$KURASHI_SETTINGS_PAGE\" > \"$(dirname \"$0\")/launched-page\"\n\
         printf '%s' \"$KURASHI_SETTINGS_KEY\" > \"$(dirname \"$0\")/launched\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&qs, std::fs::Permissions::from_mode(0o755)).unwrap();
    (settings, bin)
}

async fn wait_for(path: &Path) -> String {
    for _ in 0..200 {
        if let Ok(text) = std::fs::read_to_string(path) {
            return text;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("{} never appeared", path.display());
}

#[tokio::test]
async fn settings_open_launches_the_window_with_the_key_or_jumps_a_running_one() {
    let dir = root("open");
    let (settings, bin) = fake_qs(&dir);
    let app = SettingsApp {
        dir: settings,
        path: bin.clone().into_os_string(),
    };
    let fx = open(&dir, app);

    let opened = fx
        .call("settings.open", json!({"key": "bar.height"}))
        .await
        .unwrap();
    assert_eq!(opened, json!({"opened": "launched"}));
    assert_eq!(wait_for(&bin.join("launched")).await, "bar.height");

    // A window that runs takes the key through IPC instead of a second window.
    std::fs::write(bin.join("running"), "").unwrap();
    std::fs::remove_file(bin.join("launched")).unwrap();
    let opened = fx
        .call("settings.open", json!({"key": "theme.colors.palette"}))
        .await
        .unwrap();
    assert_eq!(opened, json!({"opened": "jumped"}));
    assert!(!bin.join("launched").exists());

    // Unknown keys are refused with the schema's message key, nothing starts.
    let err = fx
        .call("settings.open", json!({"key": "bar.hieght"}))
        .await
        .unwrap_err();
    assert_eq!(err, ActionError::Invalid("error.config.unknown_key".into()));
    let _ = std::fs::remove_dir_all(&dir);
}

/// I40 (K65): `settings.open {page}` opens Settings on a schema page or a loaded mod's page
/// (`mod:<id>`): a new window gets `KURASHI_SETTINGS_PAGE`, a running one `ipc call settings page`.
/// A page Settings does not have is refused before anything starts; a key wins over a page.
#[tokio::test]
async fn settings_open_takes_a_page_and_refuses_one_settings_does_not_have() {
    let dir = root("page");
    let (settings, bin) = fake_qs(&dir);
    let app = SettingsApp {
        dir: settings,
        path: bin.clone().into_os_string(),
    };
    let fx = open(&dir, app);

    let opened = fx
        .call("settings.open", json!({"page": "keys"}))
        .await
        .unwrap();
    assert_eq!(opened, json!({"opened": "launched"}));
    assert_eq!(wait_for(&bin.join("launched")).await, "");
    assert_eq!(wait_for(&bin.join("launched-page")).await, "keys");

    for bad in ["bogus", "@mods", "mod:", "mod:media", "mods.media", ""] {
        let err = fx
            .call("settings.open", json!({"page": bad}))
            .await
            .unwrap_err();
        let want = if bad.is_empty() {
            "error.args.invalid"
        } else {
            "error.settings.unknown_page"
        };
        assert_eq!(err, ActionError::Invalid(want.into()), "page {bad:?}");
    }
    let err = fx
        .call("settings.open", json!({"page": 3}))
        .await
        .unwrap_err();
    assert_eq!(err, ActionError::Invalid("error.args.invalid".into()));

    // A loaded mod has a page (K25), `mods.<id>` in `schema.settings`, linked as `mod:<id>`.
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let mut reg = kurashi_mods::Registry::discover(
        &[PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods")],
        &version,
    );
    reg.load("media").unwrap();
    fx.store.sync_mods(&reg);

    // A running window takes the page through IPC, with the id as given.
    std::fs::write(bin.join("running"), "").unwrap();
    let opened = fx
        .call("settings.open", json!({"page": "mod:media"}))
        .await
        .unwrap();
    assert_eq!(opened, json!({"opened": "jumped"}));
    assert_eq!(wait_for(&bin.join("ipc")).await, "page mod:media");

    // Key and page: the key wins (PROTOCOL §6, the page only when no key is given).
    std::fs::remove_file(bin.join("ipc")).unwrap();
    let opened = fx
        .call(
            "settings.open",
            json!({"key": "bar.height", "page": "bogus"}),
        )
        .await
        .unwrap();
    assert_eq!(opened, json!({"opened": "jumped"}));
    assert_eq!(wait_for(&bin.join("ipc")).await, "jump bar.height");
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn settings_open_says_when_settings_or_qs_is_missing() {
    let dir = root("missing");
    let (settings, bin) = fake_qs(&dir);
    let not_installed = open(
        &dir,
        SettingsApp {
            dir: dir.join("nothing"),
            path: bin.clone().into_os_string(),
        },
    );
    let err = not_installed
        .call("settings.open", json!({}))
        .await
        .unwrap_err();
    assert_eq!(
        err,
        ActionError::Unavailable("error.settings.not_installed".into())
    );
    let no_qs = open(
        &dir,
        SettingsApp {
            dir: settings,
            path: Default::default(),
        },
    );
    let err = no_qs.call("settings.open", json!({})).await.unwrap_err();
    assert_eq!(
        err,
        ActionError::Unavailable("error.settings.no_runtime".into())
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// Every core face the island registers has a label, and the label has a catalogue entry in both
/// languages (I37, rule 8).
#[tokio::test]
async fn island_face_offers_have_labels_in_both_catalogues() {
    let dir = root("faces");
    let fx = open(&dir, unset_app());
    let _island = IslandHost::new(
        fx.hub.clone(),
        "main",
        IslandConfig {
            faces: vec!["clock".into()],
            default: "clock".into(),
            ..Default::default()
        },
        &CORE_FACES,
    );
    fx.store.refresh_choices();

    let (_, settings) = fx.hub.snapshot("schema.settings").unwrap();
    let row = settings["pages"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|p| p["sections"].as_array().into_iter().flatten())
        .flat_map(|s| s["rows"].as_array().into_iter().flatten())
        .find(|r| r["choices_from"] == "island.faces")
        .expect("a row of the island page offers island.faces")
        .clone();
    let labels: Vec<(String, String)> = row["choices"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            (
                c["value"].as_str().unwrap().into(),
                c["label"].as_str().unwrap().into(),
            )
        })
        .collect();
    let mut offered: Vec<&str> = labels.iter().map(|(v, _)| v.as_str()).collect();
    offered.sort();
    assert_eq!(
        offered,
        vec!["bluetooth", "clock", "media", "notifications", "power"],
        "the transient OSD faces are not offered"
    );

    let catalogue = |lang: &str| -> toml::Table {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../i18n")
            .join(lang)
            .join("config.toml");
        std::fs::read_to_string(&path).unwrap().parse().unwrap()
    };
    for lang in ["en", "ja"] {
        let table = catalogue(lang);
        for face in CORE_FACES {
            assert!(
                table.contains_key(&format!("config.face.{face}")),
                "{lang}: config.face.{face} missing"
            );
        }
    }
    for (value, label) in labels {
        assert_eq!(label, format!("config.face.{value}"));
    }
    let _ = std::fs::remove_dir_all(&dir);
}
