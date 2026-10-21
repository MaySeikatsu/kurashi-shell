//! Shōjiki (rule 2) over every schema key, black-box over the socket (card M5-honesty): what the
//! daemon reports is what is in effect, with its provenance, and a reason whenever a control is
//! inert. Each test collects every violation before it fails, so one run names every bad key.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use kurashi_config::{FORCED_NIX, Options, Paths, REASON_NIX_ENFORCED};
use kurashi_core::{Provenanced, Source};
use kurashi_ipc::{ApplyOp, ClientMsg, LayerValue, LineReader, ServerMsg, write_msg};
use kurashi_schema::{Coupling, FieldType, KeyMeta, RecordField, Registry, Ty};
use kurashid::config::ConfigStore;
use kurashid::{ActionRegistry, Daemon, Hub, Intents};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};

const A11Y_LAYER: &str = "accessibility";
const A11Y_REASON: &str = "settings.inert.overridden_by";
const REQUIRES_REASON: &str = "settings.inert.requires";
const PENDING_RESTART: &str = "settings.pending.restart";
const INERT_REASONS: [&str; 3] = [
    REQUIRES_REASON,
    "settings.inert.capability",
    "settings.inert.overridden_by",
];

fn registry() -> &'static Registry {
    kurashi_schema::v1::registry()
}

struct Client {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Client {
    async fn call(&mut self, m: ClientMsg) -> ServerMsg {
        write_msg(&mut self.wr, &m).await.unwrap();
        tokio::time::timeout(Duration::from_secs(5), self.rd.next_value())
            .await
            .expect("daemon silent for 5 s")
            .unwrap()
            .expect("socket closed")
    }

    /// `cfg.get`: the effective value with its provenance.
    async fn get(&mut self, key: &str, output: Option<&str>) -> Provenanced {
        let m = ClientMsg::CfgGet {
            id: "get".into(),
            key: key.into(),
            output: output.map(Into::into),
        };
        match self.call(m).await {
            ServerMsg::CfgVal { v, .. } => v,
            other => panic!("cfg.get {key}: {other:?}"),
        }
    }

    /// `cfg.explain`: every layer, lowest precedence first.
    async fn explain(&mut self, key: &str) -> Vec<LayerValue> {
        let m = ClientMsg::CfgExplain {
            id: "explain".into(),
            key: key.into(),
            output: None,
        };
        match self.call(m).await {
            ServerMsg::CfgWhy { layers, .. } => layers,
            other => panic!("cfg.explain {key}: {other:?}"),
        }
    }

    /// The `config` document as the daemon serves it now (PROTOCOL §3 resync, no patch merging).
    async fn config_doc(&mut self) -> Value {
        match self
            .call(ClientMsg::Resync {
                doc: "config".into(),
            })
            .await
        {
            ServerMsg::Snap { data, .. } => data,
            other => panic!("resync config: {other:?}"),
        }
    }

    async fn apply(&mut self, ops: Vec<ApplyOp>) -> ServerMsg {
        self.call(ClientMsg::Apply {
            id: "apply".into(),
            ops,
            dry_run: false,
        })
        .await
    }
}

/// A daemon over a fresh config dir on its own socket (the setup of `tests/config.rs`).
/// `managed` is written to `managed.toml` before the store opens: the Home-Manager layer.
async fn start(managed: Option<String>) -> Client {
    start_with(managed, None).await
}

/// [`start`], with the mods of `mods` discovered and synced into the store (K22).
async fn start_with(managed: Option<String>, mods: Option<&kurashi_mods::Registry>) -> Client {
    static N: AtomicUsize = AtomicUsize::new(0);
    let n = N.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!("kurashid-honesty-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    let paths = Paths::rooted(&root);
    if let Some(text) = managed {
        std::fs::create_dir_all(&paths.config_dir).unwrap();
        std::fs::write(paths.managed_file(), text).unwrap();
    }
    let sock = root.join("ipc.sock");

    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    let store = ConfigStore::open(hub.clone(), registry(), paths, Options::default());
    if let Some(reg) = mods {
        store.sync_mods(reg);
    }
    store.register_actions(&mut actions);
    let mut daemon = Daemon::new(hub, actions, Intents::default());
    daemon.config = Some(store);
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    tokio::spawn(kurashid::server::serve(
        listener,
        Arc::new(daemon),
        std::future::pending(),
    ));

    let (rd, wr) = UnixStream::connect(&sock).await.unwrap().into_split();
    let mut client = Client {
        rd: LineReader::new(rd),
        wr,
    };
    let welcome = client
        .call(ClientMsg::Hello {
            v: 1,
            client: "honesty".into(),
            caps: vec![],
            scope: None,
        })
        .await;
    assert!(matches!(welcome, ServerMsg::Welcome { .. }), "{welcome:?}");
    client
}

fn set(key: &str, value: Value) -> ApplyOp {
    ApplyOp::Set {
        set: key.into(),
        value,
        output: None,
    }
}

/// A valid value that differs from the default, derived from the key's schema alone.
fn non_default(m: &KeyMeta) -> Value {
    let (d, c) = (&m.default, &m.constraints);
    match m.ty {
        Ty::Bool => json!(!d.as_bool().unwrap_or(false)),
        // The range bounds are on-step by construction; a bound equal to the default gives way to the other.
        Ty::Int | Ty::Float => match (&c.min, &c.max) {
            (Some(lo), Some(hi)) if lo != d => lo.clone(),
            (Some(_), Some(hi)) => hi.clone(),
            // No range: the generated value fails validation, which the test reports as a harness error.
            _ => json!(d.as_f64().unwrap_or(0.0) + 1.0),
        },
        Ty::Choice => c
            .choices
            .iter()
            .map(|ch| json!(ch.value))
            .find(|v| v != d)
            .unwrap_or_else(|| d.clone()),
        Ty::String => json!(format!("{}-x", d.as_str().unwrap_or_default())),
        Ty::StringList => {
            let mut items = d.as_array().cloned().unwrap_or_default();
            items.push(json!("probe"));
            Value::Array(items)
        }
        Ty::Font => json!(["Probe Sans"]),
        Ty::Action => json!("honesty.probe"),
        Ty::Color => json!("#123456"),
        // One row of probe values, one per declared field (K38): the default is an empty list.
        Ty::Records => {
            let spec = c.record.clone().unwrap_or_default();
            let row: serde_json::Map<String, Value> = spec
                .fields
                .iter()
                .map(|f| (f.key.clone(), probe_field(f)))
                .collect();
            json!([row])
        }
    }
}

/// A valid probe value for one declared field of a records key (K38).
fn probe_field(f: &RecordField) -> Value {
    match f.ty {
        FieldType::String => json!("probe"),
        FieldType::Url => json!(format!(
            "{}://probe",
            f.schemes.first().map_or("https", String::as_str)
        )),
        FieldType::Enum => json!(f.choices.first().cloned().unwrap_or_default()),
        FieldType::Bool => json!(true),
        FieldType::Int => json!(f.range.map_or(1, |(lo, _)| lo)),
    }
}

/// mode key -> (coupled key, forced value), straight from the schema's `overridden_by` couplings.
fn overrides_by_mode() -> BTreeMap<String, Vec<(String, Value)>> {
    let mut by_mode: BTreeMap<String, Vec<(String, Value)>> = BTreeMap::new();
    for m in registry().iter() {
        for c in &m.couplings {
            if let Coupling::OverriddenBy {
                key: mode,
                forces: Some(v),
            } = c
            {
                by_mode
                    .entry(mode.clone())
                    .or_default()
                    .push((m.key.clone(), v.clone()));
            }
        }
    }
    by_mode
}

/// The Shōjiki invariant for every key, right now: `cfg.get` is the one active layer of
/// `cfg.explain` (value, source, reason), and the `config` document carries the same provenance.
async fn audit(client: &mut Client, scenario: &str, bad: &mut Vec<String>) {
    let keys: Vec<String> = registry().iter().map(|m| m.key.clone()).collect();
    audit_keys(client, &keys, scenario, bad).await;
}

/// [`audit`] for the named keys (a mod's setting is not in the core registry, K22).
async fn audit_keys(client: &mut Client, keys: &[String], scenario: &str, bad: &mut Vec<String>) {
    let doc = client.config_doc().await;
    for key in keys {
        let key = key.as_str();
        let p = client.get(key, None).await;
        let layers = client.explain(key).await;
        let active: Vec<&LayerValue> = layers.iter().filter(|l| l.active).collect();
        let reason = p.reason.as_ref().or(p.forced_by.as_ref());
        match active.as_slice() {
            [a] if a.source == p.source && a.value == p.value && a.reason.as_ref() == reason => {}
            [a] => bad.push(format!(
                "[{scenario}] {key}: cfg.get says {p:?}, the active layer says {a:?}"
            )),
            _ => bad.push(format!(
                "[{scenario}] {key}: {} active layers in cfg.explain",
                active.len()
            )),
        }
        if doc["values"][key] != json!(&p) {
            bad.push(format!(
                "[{scenario}] {key}: config doc says {}, cfg.get says {p:?}",
                doc["values"][key]
            ));
        }
    }
}

/// What `key` is at rest: the default style's theme layer (K53: the style washi on its look) where it recommends a
/// value, else the schema default.
fn at_rest(key: &str) -> (Value, Source) {
    use kurashi_theme::appearance::{Kind, find, layer};
    let style = find(Kind::Style, "washi").expect("default style");
    let look = find(Kind::Look, &style.look);
    layer(Some(&style), look.as_ref())
        .into_iter()
        .find(|e| e.0 == key)
        .map(|(_, v, src)| (v, Source::Theme(src)))
        .unwrap_or_else(|| {
            (
                registry().get(key).expect("key").default.clone(),
                Source::Default,
            )
        })
}

/// Step 1 on the untouched store: every key reports the value at rest — its schema default as `default`, or the default
/// style's recommendation as `theme:` — with the layer in effect.
#[tokio::test]
async fn every_key_reports_the_layer_in_effect_at_defaults() {
    let mut client = start(None).await;
    let mut bad = Vec::new();
    for m in registry().iter() {
        let p = client.get(&m.key, None).await;
        if (p.value.clone(), p.source.clone()) != at_rest(&m.key) {
            bad.push(format!("{}: default reported as {p:?}", m.key));
        }
    }
    audit(&mut client, "defaults", &mut bad).await;
    assert!(bad.is_empty(), "{bad:#?}");
}

/// Step 2: a valid non-default user value shows as `user` everywhere, and reset restores the
/// default. Per-output keys also get an output-scoped value that only its own output shows.
#[tokio::test]
async fn user_values_show_as_user_and_reset_restores_default() {
    let mut bad = Vec::new();
    for m in registry().iter() {
        let key = m.key.as_str();
        let value = non_default(m);
        if let Err(e) = registry().validate(key, &value) {
            bad.push(format!(
                "harness: {key}: generated {value} is invalid: {e:?}"
            ));
            continue;
        }

        let mut client = start(None).await;
        let reply = client.apply(vec![set(key, value.clone())]).await;
        if !matches!(reply, ServerMsg::Applied { .. }) {
            bad.push(format!("{key}: valid value {value} rejected: {reply:?}"));
            continue;
        }
        let p = client.get(key, None).await;
        if p.value != value || p.source != Source::User {
            bad.push(format!("{key}: set {value}, cfg.get says {p:?}"));
        }
        audit(&mut client, &format!("{key}=set"), &mut bad).await;

        let reset = ApplyOp::Reset {
            reset: key.into(),
            output: None,
        };
        if !matches!(client.apply(vec![reset]).await, ServerMsg::Applied { .. }) {
            bad.push(format!("{key}: reset rejected"));
            continue;
        }
        let p = client.get(key, None).await;
        if (p.value.clone(), p.source.clone()) != at_rest(key) {
            bad.push(format!(
                "{key}: reset should restore the default, cfg.get says {p:?}"
            ));
        }
        audit(&mut client, &format!("{key}=reset"), &mut bad).await;

        if m.flags.per_output {
            per_output_check(key, m.default.clone(), value, &mut bad).await;
        }
    }
    assert!(bad.is_empty(), "{bad:#?}");
}

async fn per_output_check(key: &str, default: Value, value: Value, bad: &mut Vec<String>) {
    let mut client = start(None).await;
    let on_dp1 = ApplyOp::Set {
        set: key.into(),
        value: value.clone(),
        output: Some("DP-1".into()),
    };
    if !matches!(client.apply(vec![on_dp1]).await, ServerMsg::Applied { .. }) {
        bad.push(format!("{key}@DP-1: valid per-output value rejected"));
        return;
    }
    let own = client.get(key, Some("DP-1")).await;
    if own.value != value || own.source != Source::User {
        bad.push(format!("{key}@DP-1: set {value}, cfg.get says {own:?}"));
    }
    let other = client.get(key, Some("DP-2")).await;
    if other.value != default || other.source != Source::Default {
        bad.push(format!(
            "{key}@DP-2: a DP-1 value leaked into DP-2: {other:?}"
        ));
    }
    let doc = client.config_doc().await;
    if doc["outputs"]["DP-1"][key] != json!(&own) {
        bad.push(format!(
            "{key}@DP-1: config doc disagrees with cfg.get {own:?}"
        ));
    }
    let reset = ApplyOp::Reset {
        reset: key.into(),
        output: Some("DP-1".into()),
    };
    if !matches!(client.apply(vec![reset]).await, ServerMsg::Applied { .. }) {
        bad.push(format!("{key}@DP-1: per-output reset rejected"));
        return;
    }
    let back = client.get(key, Some("DP-1")).await;
    if back.value != default || back.source != Source::Default {
        bad.push(format!("{key}@DP-1: per-output reset left {back:?}"));
    }
}

/// Step 3: a key pinned by an enforced managed layer shows `forced:nix` with its reason. A user
/// set on it may be accepted or rejected, but the effective value stays the pinned one.
#[tokio::test]
async fn enforced_managed_value_pins_the_key_and_masks_the_user_set() {
    let mut bad = Vec::new();
    for m in registry().iter() {
        let key = m.key.as_str();
        let pinned = non_default(m);
        let managed = format!(
            "{key} = {}\n\n[_managed]\nenforce = true\n",
            kurashi_schema::toml_value(&pinned)
        );
        let want = Provenanced {
            value: pinned.clone(),
            source: Source::Forced(FORCED_NIX.into()),
            forced_by: Some(FORCED_NIX.into()),
            reason: Some(REASON_NIX_ENFORCED.into()),
            inert_by: None,
        };

        let mut client = start(Some(managed)).await;
        let p = client.get(key, None).await;
        if p != want {
            bad.push(format!(
                "{key}: pinned to {pinned}, expected {want:?}, cfg.get says {p:?}"
            ));
        }
        // The user asks for the schema default, which the pin overrides.
        let reply = client.apply(vec![set(key, m.default.clone())]).await;
        if !matches!(
            reply,
            ServerMsg::Applied { .. } | ServerMsg::Rejected { .. }
        ) {
            bad.push(format!("{key}: unexpected reply to a user set: {reply:?}"));
        }
        let after = client.get(key, None).await;
        if after != want {
            bad.push(format!(
                "{key}: the user set leaked past the pin: {after:?}"
            ));
        }
        audit(&mut client, &format!("{key}=pinned"), &mut bad).await;
    }
    assert!(bad.is_empty(), "{bad:#?}");
}

/// Step 4: switching an accessibility mode on forces every key it overrides, and each forced key
/// names the mode and the reason; switching it off hands the key back to its default.
#[tokio::test]
async fn a11y_modes_force_their_coupled_keys_with_a_reason() {
    let by_mode = overrides_by_mode();
    assert!(
        !by_mode.is_empty(),
        "the schema declares accessibility overrides"
    );
    let mut bad = Vec::new();
    for (mode, coupled) in &by_mode {
        let mut client = start(None).await;
        if !matches!(
            client.apply(vec![set(mode, json!(true))]).await,
            ServerMsg::Applied { .. }
        ) {
            bad.push(format!("{mode}: cannot switch on"));
            continue;
        }
        for (key, forced) in coupled {
            let want = Provenanced {
                value: forced.clone(),
                source: Source::Forced(A11Y_LAYER.into()),
                forced_by: Some(mode.clone()),
                reason: Some(A11Y_REASON.into()),
                inert_by: None,
            };
            let p = client.get(key, None).await;
            if p != want {
                bad.push(format!(
                    "{mode} on: {key} should be {want:?}, cfg.get says {p:?}"
                ));
            }
        }
        audit(&mut client, &format!("{mode}=on"), &mut bad).await;

        if !matches!(
            client.apply(vec![set(mode, json!(false))]).await,
            ServerMsg::Applied { .. }
        ) {
            bad.push(format!("{mode}: cannot switch off"));
            continue;
        }
        for (key, _) in coupled {
            let p = client.get(key, None).await;
            if (p.value.clone(), p.source.clone()) != at_rest(key) {
                bad.push(format!(
                    "{mode} off: {key} should fall back to its default, cfg.get says {p:?}"
                ));
            }
        }
        audit(&mut client, &format!("{mode}=off"), &mut bad).await;
    }
    assert!(bad.is_empty(), "{bad:#?}");
}

/// K21 (rule 2): a `restart` key that runs another value than its service started with says so
/// until it is set back. The reason is pending, not inert: the row stays editable, and the value
/// the service runs with does not change before the restart.
#[tokio::test]
async fn restart_keys_report_pending_until_set_back_to_start_up() {
    let mut bad = Vec::new();
    for m in registry().iter().filter(|m| m.flags.restart) {
        let key = m.key.as_str();
        if m.flags.per_output {
            bad.push(format!(
                "{key}: a restart key is per output, but pending-restart is tracked per key"
            ));
            continue;
        }
        let mut client = start(None).await;
        let changed = non_default(m);
        if !matches!(
            client.apply(vec![set(key, changed.clone())]).await,
            ServerMsg::Applied { .. }
        ) {
            bad.push(format!("{key}: valid value {changed} rejected"));
            continue;
        }
        let p = client.get(key, None).await;
        if p.value != changed
            || p.source != Source::User
            || p.reason.as_deref() != Some(PENDING_RESTART)
            || p.inert_by.is_some()
        {
            bad.push(format!(
                "{key}: set {changed}, expected pending restart, cfg.get says {p:?}"
            ));
        }
        audit(&mut client, &format!("{key}=pending"), &mut bad).await;

        if !matches!(
            client.apply(vec![set(key, m.default.clone())]).await,
            ServerMsg::Applied { .. }
        ) {
            bad.push(format!(
                "{key}: setting the start-up value back was rejected"
            ));
            continue;
        }
        let p = client.get(key, None).await;
        if p.value != m.default || p.reason.is_some() || p.inert_by.is_some() {
            bad.push(format!(
                "{key}: back at its start-up value, expected no reason, cfg.get says {p:?}"
            ));
        }
        audit(&mut client, &format!("{key}=back"), &mut bad).await;
    }
    assert!(bad.is_empty(), "{bad:#?}");
}

/// K21, per output: `bar.enabled` off on one output makes `bar.edge` inert there and nowhere else.
/// `bar.edge` has no value of its own on that output, so the output's entry in the `config` document
/// must carry the reason anyway: the view falls back to the global entry and does not evaluate
/// `requires` itself.
#[tokio::test]
async fn output_scoped_requires_is_reported_in_that_output_only() {
    let mut client = start(None).await;
    let off_on_dp1 = ApplyOp::Set {
        set: "bar.enabled".into(),
        value: json!(false),
        output: Some("DP-1".into()),
    };
    assert!(
        matches!(
            client.apply(vec![off_on_dp1]).await,
            ServerMsg::Applied { .. }
        ),
        "bar.enabled@DP-1 = false rejected"
    );
    let mut bad = Vec::new();
    let inert = client.get("bar.edge", Some("DP-1")).await;
    if inert.reason.as_deref() != Some(REQUIRES_REASON)
        || inert.inert_by.as_deref() != Some("bar.enabled")
    {
        bad.push(format!(
            "bar.edge@DP-1 should be inert by bar.enabled, cfg.get says {inert:?}"
        ));
    }
    for scope in [None, Some("DP-2")] {
        let p = client.get("bar.edge", scope).await;
        if p.reason.is_some() || p.inert_by.is_some() {
            bad.push(format!(
                "bar.edge@{scope:?} should be active, cfg.get says {p:?}"
            ));
        }
    }
    let doc = client.config_doc().await;
    if doc["outputs"]["DP-1"]["bar.edge"] != json!(&inert) {
        bad.push(format!(
            "config doc lists bar.edge@DP-1 as {}, cfg.get says {inert:?}",
            doc["outputs"]["DP-1"]["bar.edge"]
        ));
    }
    audit(&mut client, "bar.enabled@DP-1=off", &mut bad).await;
    assert!(bad.is_empty(), "{bad:#?}");
}

/// Goal of the card: a control the schema makes inert (a `requires` coupling, or an active
/// `overridden_by` mode) carries a reason in the daemon's report. The schema's own `blocked_by`,
/// evaluated over the daemon's effective values, gives the expected inert set.
#[tokio::test]
async fn inert_controls_report_why_they_are_inert() {
    let mut scenarios: Vec<(String, Vec<ApplyOp>)> = vec![("defaults".into(), vec![])];
    scenarios.push((
        "bar.enabled=false".into(),
        vec![set("bar.enabled", json!(false))],
    ));
    for mode in overrides_by_mode().keys() {
        scenarios.push((format!("{mode}=on"), vec![set(mode, json!(true))]));
    }

    let mut bad = Vec::new();
    for (name, ops) in scenarios {
        let mut client = start(None).await;
        if !ops.is_empty() && !matches!(client.apply(ops).await, ServerMsg::Applied { .. }) {
            bad.push(format!("[{name}] scenario could not be set up"));
            continue;
        }
        let mut shown: HashMap<String, Provenanced> = HashMap::new();
        for m in registry().iter() {
            shown.insert(m.key.clone(), client.get(&m.key, None).await);
        }
        let effective = |k: &str| shown.get(k).map(|p| p.value.clone());
        for m in registry().iter() {
            let p = &shown[&m.key];
            let blocking = m.blocked_by(&effective, &|_: &str| true);
            let expected: BTreeSet<&str> = blocking.iter().map(|c| c.reason_key()).collect();
            match p.reason.as_deref() {
                None if !expected.is_empty() => bad.push(format!(
                    "[{name}] {}: inert by {expected:?} but cfg.get gives no reason ({p:?})",
                    m.key
                )),
                Some(r) if INERT_REASONS.contains(&r) && expected.is_empty() => bad.push(format!(
                    "[{name}] {}: cfg.get says inert ({r}) but no coupling blocks it",
                    m.key
                )),
                Some(r) if INERT_REASONS.contains(&r) && !expected.contains(r) => {
                    bad.push(format!(
                        "[{name}] {}: reason {r} is not one of the blocking reasons {expected:?}",
                        m.key
                    ))
                }
                _ => {}
            }
            // K21: `inert_by` names a blocking `requires` key, and is present exactly when the
            // reason is the requires one.
            let by_requires: BTreeSet<&str> = blocking
                .iter()
                .filter_map(|c| match c {
                    Coupling::Requires { key, .. } => Some(key.as_str()),
                    _ => None,
                })
                .collect();
            match (p.reason.as_deref(), p.inert_by.as_deref()) {
                (Some(REQUIRES_REASON), Some(by)) if by_requires.contains(by) => {}
                (Some(REQUIRES_REASON), by) => bad.push(format!(
                    "[{name}] {}: requires reason with inert_by {by:?}, blocking requires keys {by_requires:?}",
                    m.key
                )),
                (_, Some(by)) => bad.push(format!(
                    "[{name}] {}: inert_by {by} without the requires reason ({p:?})",
                    m.key
                )),
                _ => {}
            }
        }
    }
    assert!(bad.is_empty(), "{bad:#?}");
}

/// The test data's `records` mod (K38), on, as the daemon discovers it.
fn records_mods() -> kurashi_mods::Registry {
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
    let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/data/mods");
    let mut reg = kurashi_mods::Registry::discover(&[dir], &version);
    reg.enable("records").unwrap();
    reg
}

/// A records key (K38) is honest like any key: the list in effect, its provenance and its reason agree
/// in `cfg.get`, `cfg.explain` and the config document, whether the user set it or Nix pinned it.
#[tokio::test]
async fn a_records_key_is_honest_when_set_and_when_pinned_by_nix() {
    const PINS: &str = "mods.records.pins";
    let keys = [PINS.to_string()];
    let mut bad = Vec::new();

    let mut client = start_with(None, Some(&records_mods())).await;
    let row = json!([{"id": "home", "title": "Home", "target": "https://example.org"}]);
    if !matches!(
        client.apply(vec![set(PINS, row)]).await,
        ServerMsg::Applied { .. }
    ) {
        bad.push("user: the list was refused".to_string());
    }
    audit_keys(&mut client, &keys, "user", &mut bad).await;

    let managed = "mods.records.pins = [{ id = \"nix\", title = \"Nix\", target = \"https://nix.example\" }]\n\n[_managed]\nenforce = true\n";
    let mut client = start_with(Some(managed.into()), Some(&records_mods())).await;
    audit_keys(&mut client, &keys, "nix", &mut bad).await;
    let p = client.get(PINS, None).await;
    if p.source != Source::Forced(FORCED_NIX.into()) || p.value[0]["id"] != "nix" {
        bad.push(format!("nix: the pinned list is not in effect: {p:?}"));
    }
    assert!(bad.is_empty(), "{bad:#?}");
}
