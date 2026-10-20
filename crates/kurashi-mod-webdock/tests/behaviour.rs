//! The web dock's daemon side, driven through the registrations a `ModCtx` collects (no daemon around it): the
//! actions, the document the service publishes, the host's state as the daemon writes it, the settings the mod
//! writes, the hover and focus deadlines (K40: reveal 250 ms, 500 ms shared, hide 400 ms) and the idle clock, on a
//! paused tokio clock. The daemon-level path (a real host process, the settings feed of the config store) is in
//! kurashid's tests.

use std::collections::BTreeMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{
    ActionError, ActionFn, FaceUpdate, Hooks, HostState, ModCtx, NativeMod, Publish, Registration,
    Settings, SettingsError, Values,
};
use kurashi_mod_webdock::{Dirs, Opener, Webdock};
use serde_json::{Value, json};
use tokio::sync::watch;

/// Records what the mod asks of the daemon: host starts and stops, and settings writes.
#[derive(Default)]
struct Recorder {
    calls: Mutex<Vec<String>>,
    writes: Mutex<Vec<(String, Value)>>,
}

impl Hooks for Recorder {
    fn face(&self, _: &str, _: FaceUpdate) {}

    fn choices_changed(&self, _: &str) {}

    fn host_start(&self, host: &str) {
        self.calls.lock().unwrap().push(format!("start {host}"));
    }

    fn host_stop(&self, host: &str) {
        self.calls.lock().unwrap().push(format!("stop {host}"));
    }

    fn set_setting(&self, key: &str, value: Value) -> Result<(), SettingsError> {
        self.writes.lock().unwrap().push((key.into(), value));
        Ok(())
    }
}

/// The system's browser, recorded.
#[derive(Default)]
struct Browser {
    opened: Mutex<Vec<String>>,
    installed: bool,
}

impl Opener for Browser {
    fn installed(&self) -> bool {
        self.installed
    }

    fn open(&self, url: &str) -> Result<(), String> {
        self.opened.lock().unwrap().push(url.into());
        Ok(())
    }
}

/// One enabled dock: its actions, its document as the service publishes it, the host state the test plays.
struct Enabled {
    actions: BTreeMap<String, ActionFn>,
    state: Arc<watch::Sender<HostState>>,
    doc: Arc<Mutex<Value>>,
    settings: watch::Sender<Values>,
    rec: Arc<Recorder>,
}

fn values(pins: Value) -> Values {
    let mut v = Values::new();
    v.insert("pins".into(), pins);
    v.insert("default_view".into(), json!("mobile"));
    v.insert("width".into(), json!(412));
    v.insert("large".into(), json!(90));
    v.insert("edge".into(), json!("right"));
    v.insert("unload_after".into(), json!(60));
    v.insert("max_loaded".into(), json!(4));
    v
}

fn pin_rows() -> Value {
    json!([
        {"id": "mail", "title": "Mail", "target": "https://mail.example.org/", "view": "default", "profile": "", "icon": ""},
        {"id": "chat", "title": "Chat", "target": "https://chat.example.org/", "view": "default", "profile": "", "icon": ""},
        {"id": "weather", "title": "Weather", "target": "mod:weather:weather", "view": "default", "profile": "", "icon": ""},
    ])
}

async fn enable(values: Values, browser: Arc<Browser>, root: &Path) -> Enabled {
    let rec = Arc::new(Recorder::default());
    let (settings, rx) = watch::channel(values);
    let provides: Vec<String> = ["service:webdock", "action:webdock.*", "host:web", "i18n"]
        .map(String::from)
        .to_vec();
    let caps: Vec<String> = ["network", "exec:qs-webengine", "exec:xdg-open", "fs:scoped"]
        .map(String::from)
        .to_vec();
    let mut ctx =
        ModCtx::new(&provides, Settings::new(rx.clone()), rec.clone()).with_capabilities(&caps);
    Webdock::with(Dirs::rooted(root), browser.clone())
        .enable(&mut ctx)
        .expect("the dock enables");
    let mut hosts = ctx.take_hosts();
    let regs = ctx.finish().expect("every registration is declared");
    let host = hosts.pop().expect("the dock declares its host");

    let doc = Arc::new(Mutex::new(Value::Null));
    let mut e = Enabled {
        actions: BTreeMap::new(),
        state: host.state,
        doc: doc.clone(),
        settings,
        rec,
    };
    for reg in regs {
        match reg {
            Registration::Action { id, handler, .. } => {
                e.actions.insert(id, handler);
            }
            Registration::Service { initial, run, .. } => {
                *doc.lock().unwrap() = initial;
                let sink = doc.clone();
                let publish: Publish = Arc::new(move |v| *sink.lock().unwrap() = v);
                tokio::spawn(run(publish, Settings::new(rx.clone())));
            }
            _ => {}
        }
    }
    e
}

impl Enabled {
    async fn act(&self, id: &str, args: Value) -> Result<Option<Value>, ActionError> {
        let handler = self
            .actions
            .get(id)
            .unwrap_or_else(|| panic!("the action {id} is registered"));
        handler(args).await
    }

    /// The document as the service last published it (the service task runs between the test's yields).
    async fn doc(&self) -> Value {
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
        self.doc.lock().unwrap().clone()
    }

    async fn pin(&self, id: &str) -> Value {
        self.doc().await["pins"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == id)
            .cloned()
            .expect("the pin is in the document")
    }

    /// The host as the daemon reports it, with the document settled.
    async fn play_host(&self, state: HostState) {
        self.state.send_replace(state);
        self.doc().await;
    }

    fn calls(&self) -> Vec<String> {
        self.rec.calls.lock().unwrap().clone()
    }
}

fn args(pairs: Value) -> Value {
    pairs
}

#[tokio::test]
async fn opening_a_site_shows_it_extended_and_starts_the_host() {
    let dir = tempdir("open");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    assert_eq!(d.doc().await["mode"], "hidden");

    d.act("webdock.open", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "extended");
    assert_eq!(doc["shown"], "mail");
    assert_eq!(d.calls(), ["start web"], "a site starts the host");

    // The doc's pins: a site has its profile and view and no icon until the host reports one.
    let mail = d.pin("mail").await;
    assert_eq!(mail["kind"], "web");
    assert_eq!(mail["view"], "mobile");
    assert_eq!(mail["profile"], "mail");
    assert_eq!(mail["loaded"], false);
    assert!(mail.get("icon").is_none());
}

#[tokio::test]
async fn a_view_pin_shows_its_card_and_does_not_start_the_host() {
    let dir = tempdir("view");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act("webdock.open", args(json!({"pin": "weather"})))
        .await
        .unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "extended");
    assert_eq!(doc["shown"], "weather");
    assert!(d.calls().is_empty(), "a view never starts the host");
    assert!(
        d.pin("weather").await.get("loaded").is_none(),
        "a view has no loaded mark"
    );
}

#[tokio::test]
async fn the_card_moves_between_hidden_compact_and_extended() {
    let dir = tempdir("card");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;

    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.collapse", args(json!({}))).await.unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "compact");
    assert!(doc.get("shown").is_none(), "collapse clears the shown pin");
    assert_eq!(doc["output"], "DP-1");

    d.act("webdock.open", args(json!({"pin": "chat"})))
        .await
        .unwrap();
    d.act("webdock.hide", args(json!({}))).await.unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "hidden");
    assert_eq!(doc["shown"], "chat", "hide keeps the shown pin");

    // Toggle from hidden reopens the shown pin's card; toggle again hides it.
    d.act("webdock.toggle", args(json!({}))).await.unwrap();
    assert_eq!(d.doc().await["mode"], "extended");
    d.act("webdock.toggle", args(json!({}))).await.unwrap();
    assert_eq!(d.doc().await["mode"], "hidden");

    // Without a shown pin the strip opens instead.
    d.act("webdock.collapse", args(json!({}))).await.unwrap();
    d.act("webdock.hide", args(json!({}))).await.unwrap();
    let mut rows = pin_rows();
    rows.as_array_mut().unwrap().clear();
    d.settings.send_replace(values(rows));
    d.act("webdock.toggle", args(json!({}))).await.unwrap();
    assert_eq!(d.doc().await["mode"], "compact");
}

#[tokio::test]
async fn the_size_toggles_and_takes_phone_or_large_only() {
    let dir = tempdir("size");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    assert_eq!(d.doc().await["size"], "phone");
    d.act("webdock.size", args(json!({}))).await.unwrap();
    assert_eq!(d.doc().await["size"], "large");
    d.act("webdock.size", args(json!({"size": "phone"})))
        .await
        .unwrap();
    assert_eq!(d.doc().await["size"], "phone");
    assert_eq!(
        d.act("webdock.size", args(json!({"size": "huge"}))).await,
        Err(ActionError::Invalid("webdock.error.size".into()))
    );
}

#[tokio::test]
async fn keep_is_the_shown_site_then_the_most_recent_up_to_the_cap_and_an_audible_one_stays() {
    let dir = tempdir("keep");
    let mut rows = Vec::new();
    for id in ["a", "b", "c", "d", "e"] {
        rows.push(json!({"id": id, "title": id, "target": format!("https://{id}.example.org/"), "view": "default", "profile": "", "icon": ""}));
    }
    let mut v = values(Value::Array(rows));
    v.insert("max_loaded".into(), json!(2));
    let d = enable(v, Arc::new(Browser::default()), &dir).await;

    // Nothing is kept while the host does not run.
    d.act("webdock.open", args(json!({"pin": "a"})))
        .await
        .unwrap();
    assert_eq!(d.doc().await["keep"], json!([]));

    d.play_host(HostState::Ready).await;
    for id in ["b", "c", "d", "e"] {
        d.act("webdock.open", args(json!({"pin": id})))
            .await
            .unwrap();
    }
    assert_eq!(
        d.doc().await["keep"],
        json!(["e", "d"]),
        "the shown pin, then the cap"
    );

    // An audible site beyond the cap is kept too, after the capped ones.
    d.act("webdock.host.loaded", args(json!({"pin": "a"})))
        .await
        .unwrap();
    d.act(
        "webdock.host.audible",
        args(json!({"pin": "a", "on": true})),
    )
    .await
    .unwrap();
    assert_eq!(d.doc().await["keep"], json!(["e", "d", "a"]));
    assert_eq!(d.pin("a").await["audible"], true);

    // The host does not stay loaded past its connection: nothing is loaded or audible then.
    d.play_host(HostState::Starting).await;
    assert_eq!(d.pin("a").await["loaded"], false);
    assert!(d.pin("a").await.get("audible").is_none());
}

#[tokio::test]
async fn a_shared_profile_shows_the_first_pins_view_and_webdock_view_writes_it_to_all() {
    let dir = tempdir("views");
    let rows = json!([
        {"id": "a", "title": "A", "target": "https://a.example.org/", "view": "default", "profile": "work", "icon": ""},
        {"id": "b", "title": "B", "target": "https://b.example.org/", "view": "desktop", "profile": "work", "icon": ""},
        {"id": "c", "title": "C", "target": "https://c.example.org/", "view": "default", "profile": "solo", "icon": ""},
    ]);
    let d = enable(values(rows), Arc::new(Browser::default()), &dir).await;
    // The first pin of "work" is mobile (the default); b's own desktop view is not what the profile shows.
    assert_eq!(d.pin("a").await["view"], "mobile");
    assert_eq!(d.pin("b").await["view"], "mobile");
    assert_eq!(d.pin("b").await["profile"], "work");
    assert_eq!(d.pin("c").await["profile"], "solo");

    d.act("webdock.view", args(json!({"pin": "b", "view": "desktop"})))
        .await
        .unwrap();
    let (key, rows) = d
        .rec
        .writes
        .lock()
        .unwrap()
        .last()
        .cloned()
        .expect("a write");
    assert_eq!(key, "pins");
    assert_eq!(
        rows[0]["view"], "desktop",
        "a shares the profile: it changes too"
    );
    assert_eq!(rows[1]["view"], "desktop");
    assert_eq!(rows[2]["view"], "default", "another profile keeps its view");
    assert_eq!(
        rows[0]["title"], "A",
        "every other field of the row is kept"
    );

    assert_eq!(
        d.act(
            "webdock.view",
            args(json!({"pin": "zzz", "view": "mobile"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );
    assert_eq!(
        d.act("webdock.view", args(json!({"pin": "b", "view": "tablet"})))
            .await,
        Err(ActionError::Invalid("webdock.error.view".into()))
    );
}

#[tokio::test]
async fn host_reports_update_the_document_and_an_icon_outside_the_cache_is_refused() {
    let dir = tempdir("reports");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.play_host(HostState::Ready).await;
    let icons = dir.join("cache").join("webdock").join("icons");

    let good = icons.join("mail.png");
    d.act(
        "webdock.host.loaded",
        args(json!({"pin": "mail", "icon": good.to_string_lossy()})),
    )
    .await
    .unwrap();
    let mail = d.pin("mail").await;
    assert_eq!(mail["loaded"], true);
    assert!(mail["icon"].as_str().unwrap().starts_with("file://"));
    assert!(mail["icon"].as_str().unwrap().ends_with("/icons/mail.png"));

    // An icon from anywhere else: the pin loads, the icon is not taken, and the report says why.
    assert_eq!(
        d.act(
            "webdock.host.loaded",
            args(json!({"pin": "chat", "icon": "/etc/passwd"})),
        )
        .await,
        Err(ActionError::Invalid("webdock.error.icon".into()))
    );
    let chat = d.pin("chat").await;
    assert_eq!(chat["loaded"], true);
    assert!(chat.get("icon").is_none());

    d.act(
        "webdock.host.blocked",
        args(json!({"pin": "chat", "permission": "camera"})),
    )
    .await
    .unwrap();
    assert_eq!(d.pin("chat").await["blocked"], json!(["camera"]));
    assert_eq!(
        d.act(
            "webdock.host.blocked",
            args(json!({"pin": "chat", "permission": "teleport"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.permission".into()))
    );

    d.act("webdock.host.crashed", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    let mail = d.pin("mail").await;
    assert_eq!(mail["error"], "webdock.error.crashed");
    assert_eq!(mail["loaded"], false);

    d.act("webdock.host.loaded", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    assert!(
        d.pin("mail").await.get("error").is_none(),
        "the next load clears the error"
    );

    d.act("webdock.host.unloaded", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    assert_eq!(d.pin("mail").await["loaded"], false);

    assert_eq!(
        d.act("webdock.host.loaded", args(json!({"pin": "nope"})))
            .await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );
}

#[tokio::test]
async fn open_in_browser_takes_web_addresses_only() {
    let dir = tempdir("browser");
    let browser = Arc::new(Browser {
        installed: true,
        ..Browser::default()
    });
    let d = enable(values(pin_rows()), browser.clone(), &dir).await;

    assert_eq!(
        d.act(
            "webdock.open_external",
            args(json!({"url": "file:///etc/passwd"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.url".into()))
    );
    assert!(browser.opened.lock().unwrap().is_empty());

    d.act(
        "webdock.open_external",
        args(json!({"url": "https://example.org/a"})),
    )
    .await
    .unwrap();
    d.act(
        "webdock.host.new_window",
        args(json!({"pin": "mail", "url": "http://example.org/b"})),
    )
    .await
    .unwrap();
    assert_eq!(
        *browser.opened.lock().unwrap(),
        ["https://example.org/a", "http://example.org/b"]
    );

    let no_browser = Arc::new(Browser::default());
    let d = enable(values(pin_rows()), no_browser, &dir).await;
    assert_eq!(
        d.act(
            "webdock.open_external",
            args(json!({"url": "https://example.org/"}))
        )
        .await,
        Err(ActionError::Unavailable("webdock.error.no_browser".into()))
    );
}

#[tokio::test]
async fn the_hosts_state_reaches_the_document_with_its_reason() {
    let dir = tempdir("host");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    assert_eq!(d.doc().await["host"], json!({"state": "off"}));

    d.play_host(HostState::Missing).await;
    assert_eq!(
        d.doc().await["host"],
        json!({"state": "missing", "reason": "mods.host.missing"})
    );

    d.play_host(HostState::Failed {
        reason: "mods.host.failed".into(),
        detail: "exit status: 3; log /s/webdock/host-web.log".into(),
    })
    .await;
    let host = d.doc().await["host"].clone();
    assert_eq!(host["state"], "failed");
    assert_eq!(host["reason"], "mods.host.failed");
    assert_eq!(
        host["detail"],
        "exit status: 3; log /s/webdock/host-web.log"
    );
}

#[tokio::test]
async fn a_settings_change_reaches_the_dock_at_once() {
    let dir = tempdir("feed");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    assert_eq!(d.doc().await["geometry"]["width"], 412);

    let mut v = values(pin_rows());
    v.insert("width".into(), json!(500));
    d.settings.send_replace(v);
    assert_eq!(d.doc().await["geometry"]["width"], 500);

    let mut rows = pin_rows();
    rows.as_array_mut().unwrap().pop();
    d.settings.send_replace(values(rows));
    assert_eq!(
        d.doc().await["pins"].as_array().unwrap().len(),
        2,
        "a removed pin is gone"
    );
    assert!(
        d.act("webdock.open", args(json!({"pin": "weather"})))
            .await
            .is_err()
    );
}

#[tokio::test(start_paused = true)]
async fn the_idle_clock_stops_the_host_after_unload_after_minutes_and_zero_means_never() {
    let dir = tempdir("idle");
    let mut v = values(pin_rows());
    v.insert("unload_after".into(), json!(1));
    let d = enable(v, Arc::new(Browser::default()), &dir).await;

    // Hidden and idle with the host up: the clock runs for a minute.
    d.play_host(HostState::Ready).await;
    tokio::time::sleep(Duration::from_secs(59)).await;
    assert!(d.calls().is_empty(), "not yet");
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(
        d.calls(),
        ["stop web"],
        "the host stops after its unload time"
    );

    // A shown site holds the host: no clock.
    let mut v = values(pin_rows());
    v.insert("unload_after".into(), json!(1));
    let shown = enable(v, Arc::new(Browser::default()), &dir).await;
    shown.play_host(HostState::Ready).await;
    shown
        .act("webdock.open", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(300)).await;
    assert!(
        !shown.calls().iter().any(|c| c == "stop web"),
        "a shown site is not idle"
    );

    // Zero: never.
    let mut v = values(pin_rows());
    v.insert("unload_after".into(), json!(0));
    let never = enable(v, Arc::new(Browser::default()), &dir).await;
    never.play_host(HostState::Ready).await;
    tokio::time::sleep(Duration::from_secs(3600)).await;
    assert!(never.calls().is_empty(), "0 = never while the mod is on");
}

/// The feed with `key` set to `value`, every other key as `base` has it.
fn with(base: &Values, key: &str, value: Value) -> Values {
    let mut v = base.clone();
    v.insert(key.into(), value);
    v
}

/// The feed after the last settings write: the config store makes a write in effect before it returns.
fn feed_last_write(d: &Enabled, base: &mut Values) {
    let (key, value) = d
        .rec
        .writes
        .lock()
        .unwrap()
        .last()
        .cloned()
        .expect("a settings write");
    base.insert(key, value);
    d.settings.send_replace(base.clone());
}

fn hover(part: &str, inside: bool, output: &str) -> Value {
    json!({"part": part, "inside": inside, "output": output})
}

async fn mode_of(d: &Enabled) -> String {
    d.doc().await["mode"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

/// The rows of the last `pins` write.
fn last_rows(d: &Enabled) -> Vec<Value> {
    let (key, rows) = d
        .rec
        .writes
        .lock()
        .unwrap()
        .last()
        .cloned()
        .expect("a settings write");
    assert_eq!(key, "pins");
    rows.as_array().expect("the rows").clone()
}

#[tokio::test(start_paused = true)]
async fn a_rest_on_the_edge_reveals_after_250_ms_and_the_last_card_comes_back() {
    let dir = tempdir("reveal");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.play_host(HostState::Ready).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hide", args(json!({}))).await.unwrap();
    assert_eq!(d.calls(), ["start web"]);

    d.act("webdock.hover", args(hover("edge", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(249)).await;
    assert_eq!(mode_of(&d).await, "hidden", "not yet at 249 ms");
    tokio::time::sleep(Duration::from_millis(2)).await;
    let doc = d.doc().await;
    assert_eq!(
        doc["mode"], "extended",
        "reopen last: the card of the shown pin"
    );
    assert_eq!(doc["shown"], "mail");
    assert_eq!(doc["output"], "DP-1");
    assert_eq!(
        d.calls(),
        ["start web", "start web"],
        "the reveal starts the host"
    );
}

#[tokio::test(start_paused = true)]
async fn an_early_leave_disarms_the_reveal() {
    let dir = tempdir("early");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act("webdock.hover", args(hover("edge", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    d.act("webdock.hover", args(hover("edge", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "hidden", "the leave disarmed the reveal");
    assert!(d.calls().is_empty(), "nothing started");
}

#[tokio::test(start_paused = true)]
async fn a_shared_edge_waits_500_ms() {
    let dir = tempdir("shared");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act(
        "webdock.hover",
        args(json!({"part": "edge", "inside": true, "output": "DP-2", "shared": true})),
    )
    .await
    .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(
        mode_of(&d).await,
        "hidden",
        "250 ms is not enough on a shared edge"
    );
    tokio::time::sleep(Duration::from_millis(250)).await;
    assert_eq!(mode_of(&d).await, "compact", "500 ms: the strip");
    assert_eq!(d.doc().await["output"], "DP-2");
}

#[tokio::test(start_paused = true)]
async fn a_shown_dock_hides_400_ms_after_the_last_part_leaves_and_entering_one_disarms_it() {
    let dir = tempdir("hide");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("card", true, "DP-1")))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(399)).await;
    assert_eq!(mode_of(&d).await, "extended", "not yet at 399 ms");
    tokio::time::sleep(Duration::from_millis(2)).await;
    assert_eq!(mode_of(&d).await, "hidden", "hidden at 400 ms");
    assert_eq!(d.doc().await["shown"], "mail", "hide keeps the shown pin");

    // Entering a part in the grace disarms the hide.
    d.act(
        "webdock.open",
        args(json!({"pin": "chat", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("strip", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(200)).await;
    d.act("webdock.hover", args(hover("strip", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "extended", "the strip is inside");
}

#[tokio::test(start_paused = true)]
async fn rapid_enter_and_leave_twenty_times_ends_in_a_consistent_state() {
    let dir = tempdir("rapid");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    for i in 0..20u64 {
        d.act("webdock.hover", args(hover("edge", i % 2 == 0, "DP-1")))
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    // The last report was a leave: no reveal, whatever the earlier enters armed.
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(mode_of(&d).await, "hidden");
    assert!(d.calls().is_empty());

    // Twenty alternations that end in an enter: one reveal, 250 ms after that enter.
    for i in 0..20u64 {
        d.act("webdock.hover", args(hover("edge", i % 2 == 0, "DP-1")))
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    d.act("webdock.hover", args(hover("edge", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(249)).await;
    assert_eq!(mode_of(&d).await, "hidden");
    tokio::time::sleep(Duration::from_millis(2)).await;
    assert_eq!(mode_of(&d).await, "compact", "one reveal, then the strip");
}

#[tokio::test(start_paused = true)]
async fn pinned_and_engaged_hold_the_dock_and_the_pin_writes_reach_it() {
    let dir = tempdir("hold");
    let mut base = values(pin_rows());
    let d = enable(base.clone(), Arc::new(Browser::default()), &dir).await;
    d.play_host(HostState::Ready).await;

    // Nothing holds it: a leave hides it after 400 ms.
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "hidden");

    // `pin` with no argument flips the value in effect; the write reaches the dock through the feed.
    d.act("webdock.pin", args(json!({}))).await.unwrap();
    assert_eq!(
        d.rec.writes.lock().unwrap().last().unwrap().clone().0,
        "pinned"
    );
    feed_last_write(&d, &mut base);
    assert_eq!(d.doc().await["pinned"], true);
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(mode_of(&d).await, "extended", "pinned holds it");

    // Unpinned again with nothing inside: the hide is armed (it hides after 400 ms).
    d.act("webdock.pin", args(json!({"on": false})))
        .await
        .unwrap();
    feed_last_write(&d, &mut base);
    tokio::time::sleep(Duration::from_millis(450)).await;
    assert_eq!(
        mode_of(&d).await,
        "hidden",
        "unpinned: the rules apply again"
    );

    // Keyboard focus holds it too; losing it is a leave.
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.engage", args(json!({"on": true})))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "extended", "engaged holds it");
    d.act("webdock.engage", args(json!({"on": false})))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(450)).await;
    assert_eq!(mode_of(&d).await, "hidden", "focus left: a leave");
}

#[tokio::test(start_paused = true)]
async fn an_engage_handoff_from_strip_to_card_does_not_hide() {
    let dir = tempdir("handoff");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("strip", true, "DP-1")))
        .await
        .unwrap();
    d.act("webdock.engage", args(json!({"on": true})))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("card", true, "DP-1")))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("strip", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "extended", "the card is inside");
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "extended", "the focus holds it");
    d.act("webdock.engage", args(json!({"on": false})))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(450)).await;
    assert_eq!(mode_of(&d).await, "hidden");
}

#[tokio::test(start_paused = true)]
async fn other_output_events_are_ignored_while_the_dock_is_shown() {
    let dir = tempdir("output");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hover", args(hover("card", true, "DP-1")))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("card", false, "DP-2")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(
        mode_of(&d).await,
        "extended",
        "DP-2's leave does not hide DP-1's dock"
    );
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(450)).await;
    assert_eq!(mode_of(&d).await, "hidden");
}

#[tokio::test(start_paused = true)]
async fn reopen_last_and_hover_follow_their_settings() {
    let dir = tempdir("settings-hover");
    let base = with(&values(pin_rows()), "reopen_last", json!(false));
    let d = enable(base, Arc::new(Browser::default()), &dir).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "chat", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.hide", args(json!({}))).await.unwrap();
    d.act("webdock.hover", args(hover("edge", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(260)).await;
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "compact", "reopen last off: the strip only");
    assert_eq!(doc["shown"], "chat", "the pin is kept for the next open");

    let off = with(&values(pin_rows()), "hover", json!(false));
    let d = enable(off, Arc::new(Browser::default()), &dir).await;
    d.act("webdock.hover", args(hover("edge", true, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "hidden", "hover off ignores the edge");
    assert_eq!(d.doc().await["hover"], false);
}

#[tokio::test(start_paused = true)]
async fn toggle_engages_the_dock_and_back_steps_it_down() {
    let dir = tempdir("toggle");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.act("webdock.open", args(json!({"pin": "chat"})))
        .await
        .unwrap();
    d.act("webdock.hide", args(json!({}))).await.unwrap();

    d.act("webdock.toggle", args(json!({"output": "DP-1"})))
        .await
        .unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "extended");
    assert_eq!(doc["engaged"], true, "a toggle takes the keyboard");
    d.act("webdock.hover", args(hover("card", true, "DP-1")))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("card", false, "DP-1")))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(mode_of(&d).await, "extended", "engaged: no hide");

    d.act("webdock.back", args(json!({}))).await.unwrap();
    assert_eq!(mode_of(&d).await, "compact", "extended to compact");
    assert!(d.doc().await.get("shown").is_none());
    d.act("webdock.back", args(json!({}))).await.unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "hidden", "compact to hidden (not pinned)");
    assert_eq!(doc["engaged"], false);
    d.act("webdock.toggle", args(json!({}))).await.unwrap();
    d.act("webdock.toggle", args(json!({}))).await.unwrap();
    assert_eq!(mode_of(&d).await, "hidden", "toggle twice hides");

    // Select: a click on the shown pin's icon puts its card away and keeps the pin loaded.
    d.play_host(HostState::Ready).await;
    d.act(
        "webdock.select",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    assert_eq!(mode_of(&d).await, "extended");
    d.act("webdock.select", args(json!({"pin": "mail"})))
        .await
        .unwrap();
    let doc = d.doc().await;
    assert_eq!(doc["mode"], "compact");
    assert!(doc.get("shown").is_none());
    assert_eq!(
        doc["keep"][0], "mail",
        "the pin stays loaded, most recent first"
    );
    assert_eq!(
        d.act("webdock.select", args(json!({"pin": "zzz"}))).await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );
}

#[tokio::test(start_paused = true)]
async fn a_crashed_host_takes_its_card_and_its_focus_with_it() {
    let dir = tempdir("crash");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    d.play_host(HostState::Ready).await;
    d.act(
        "webdock.open",
        args(json!({"pin": "mail", "output": "DP-1"})),
    )
    .await
    .unwrap();
    d.act("webdock.engage", args(json!({"on": true})))
        .await
        .unwrap();
    d.act("webdock.hover", args(hover("card", true, "DP-1")))
        .await
        .unwrap();
    d.play_host(HostState::Failed {
        reason: "mods.host.failed".into(),
        detail: "exit status: 3".into(),
    })
    .await;
    // The card's leave never comes: the host's failure forgets it, and the focus with it.
    tokio::time::sleep(Duration::from_millis(450)).await;
    assert_eq!(
        mode_of(&d).await,
        "hidden",
        "nothing holds the dock any more"
    );
}

#[tokio::test(start_paused = true)]
async fn the_hover_and_focus_actions_check_their_arguments() {
    let dir = tempdir("args");
    let d = enable(values(pin_rows()), Arc::new(Browser::default()), &dir).await;
    let argument = Err(ActionError::Invalid("webdock.error.argument".into()));
    assert_eq!(
        d.act(
            "webdock.hover",
            args(json!({"part": "nope", "inside": true, "output": "DP-1"}))
        )
        .await,
        argument
    );
    assert_eq!(
        d.act(
            "webdock.hover",
            args(json!({"part": "edge", "inside": true}))
        )
        .await,
        argument,
        "an output is required"
    );
    assert_eq!(
        d.act("webdock.engage", args(json!({"on": "yes"}))).await,
        argument
    );
    assert_eq!(
        d.act("webdock.pin", args(json!({"on": "yes"}))).await,
        argument
    );
    assert_eq!(d.act("webdock.add", args(json!({}))).await, argument);
    assert_eq!(
        d.act("webdock.move", args(json!({"pin": "mail"}))).await,
        argument
    );
}

#[tokio::test]
async fn add_remove_move_and_retarget_write_the_rows_and_keep_their_other_fields() {
    let dir = tempdir("rows");
    let mut base = values(pin_rows());
    let d = enable(base.clone(), Arc::new(Browser::default()), &dir).await;

    // add: the id is the host without www., and a second add to the same host takes the next suffix.
    let reply = d
        .act(
            "webdock.add",
            args(json!({"url": "https://www.example.org/x"})),
        )
        .await
        .unwrap();
    assert_eq!(reply, Some(json!({"pin": "example-org"})));
    let rows = last_rows(&d);
    assert_eq!(rows[3]["title"], "www.example.org", "the title is the host");
    assert_eq!(rows[0]["icon"], "", "the other rows keep their fields");
    feed_last_write(&d, &mut base);
    let pin = d.pin("example-org").await;
    assert_eq!(pin["kind"], "web");
    assert_eq!(pin["view"], "mobile", "a new pin takes the default view");

    let reply = d
        .act(
            "webdock.add",
            args(json!({"url": "https://example.org/y", "title": "Docs"})),
        )
        .await
        .unwrap();
    assert_eq!(reply, Some(json!({"pin": "example-org-2"})));
    feed_last_write(&d, &mut base);
    assert_eq!(d.pin("example-org-2").await["title"], "Docs");

    // add refuses an address that is not a site.
    assert_eq!(
        d.act("webdock.add", args(json!({"url": "javascript:alert(1)"})))
            .await,
        Err(ActionError::Invalid("webdock.error.address".into()))
    );

    // move: to the front, and an index past the end is the last place.
    d.act("webdock.move", args(json!({"pin": "example-org", "to": 0})))
        .await
        .unwrap();
    assert_eq!(last_rows(&d)[0]["id"], "example-org");
    feed_last_write(&d, &mut base);
    d.act("webdock.move", args(json!({"pin": "mail", "to": 99})))
        .await
        .unwrap();
    assert_eq!(
        last_rows(&d).last().unwrap()["id"],
        "mail",
        "clamped to the end"
    );
    feed_last_write(&d, &mut base);

    // retarget: a web pin takes the page's address; a view pin and javascript are refused.
    d.act(
        "webdock.retarget",
        args(json!({"pin": "mail", "url": "file:///home/u/a.html"})),
    )
    .await
    .unwrap();
    let rows = last_rows(&d);
    let mail = rows.iter().find(|r| r["id"] == "mail").unwrap();
    assert_eq!(mail["target"], "file:///home/u/a.html");
    assert_eq!(mail["title"], "Mail", "every other field stays");
    assert_eq!(mail["view"], "default");
    assert_eq!(
        d.act(
            "webdock.retarget",
            args(json!({"pin": "weather", "url": "https://x.example.org/"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.not_a_site".into())),
        "a view pin has no address to replace"
    );
    assert_eq!(
        d.act(
            "webdock.retarget",
            args(json!({"pin": "mail", "url": "javascript:alert(1)"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.address".into()))
    );

    // remove: the row goes, the others stay as they were.
    feed_last_write(&d, &mut base);
    d.act("webdock.remove", args(json!({"pin": "chat"})))
        .await
        .unwrap();
    let rows = last_rows(&d);
    assert!(rows.iter().all(|r| r["id"] != "chat"));
    assert_eq!(rows.len(), 4, "mail, weather, example-org, example-org-2");
    assert_eq!(
        d.act("webdock.remove", args(json!({"pin": "zzz"}))).await,
        Err(ActionError::Invalid("webdock.error.unknown_pin".into()))
    );

    // A view on a view pin is not a site's view.
    assert_eq!(
        d.act(
            "webdock.view",
            args(json!({"pin": "weather", "view": "desktop"}))
        )
        .await,
        Err(ActionError::Invalid("webdock.error.not_a_site".into()))
    );
}

/// A directory for one test, empty: the dock's directories live under it.
fn tempdir(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("w20-dmn-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
