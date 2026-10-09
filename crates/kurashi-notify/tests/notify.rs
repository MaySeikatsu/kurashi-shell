mod common;

use std::collections::HashMap;
use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use futures_util::StreamExt;
use kurashi_notify::{Commands, NotifyConfig, NotifyHandle, Server};
use tokio::sync::mpsc;
use zbus::zvariant::{StructureBuilder, Value};
use zbus::{Connection, MatchRule, MessageStream};

type Hints = HashMap<&'static str, Value<'static>>;

struct Fixture {
    _bus: TestBus,
    rec: std::sync::Arc<Rec>,
    cmds: Commands,
    _handle: NotifyHandle,
    client: Connection,
    dest: String,
    sigs: mpsc::UnboundedReceiver<String>,
    cache: tempfile::TempDir,
}

async fn fixture(tweak: impl FnOnce(&mut NotifyConfig)) -> Fixture {
    let bus = TestBus::start();
    let rec = Rec::new();
    let server = bus.conn().await;
    let dest = server.unique_name().unwrap().to_string();
    let cache = tempfile::tempdir().unwrap();
    let mut cfg = NotifyConfig::new(cache.path().join("img"));
    cfg.claim_name = false;
    tweak(&mut cfg);
    let (handle, cmds) = Server::serve(server, rec.clone(), cfg).await.unwrap();

    let client = bus.conn().await;
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.Notifications")
        .unwrap()
        .build();
    let mut stream = MessageStream::for_match_rule(rule, &client, None)
        .await
        .unwrap();
    let (tx, sigs) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        while let Some(Ok(m)) = stream.next().await {
            let h = m.header();
            let member = h.member().unwrap().to_string();
            let body = m.body();
            let s = match member.as_str() {
                "NotificationClosed" => {
                    let (id, r): (u32, u32) = body.deserialize().unwrap();
                    format!("closed:{id}:{r}")
                }
                "ActionInvoked" => {
                    let (id, k): (u32, String) = body.deserialize().unwrap();
                    format!("action:{id}:{k}")
                }
                "NotificationReplied" => {
                    let (id, t): (u32, String) = body.deserialize().unwrap();
                    format!("replied:{id}:{t}")
                }
                _ => continue,
            };
            let _ = tx.send(s);
        }
    });
    Fixture {
        _bus: bus,
        rec,
        cmds,
        _handle: handle,
        client,
        dest,
        sigs,
        cache,
    }
}

impl Fixture {
    async fn notify(
        &self,
        replaces: u32,
        summary: &str,
        body: &str,
        actions: &[&str],
        hints: Hints,
        timeout: i32,
    ) -> u32 {
        let actions: Vec<String> = actions.iter().map(|s| s.to_string()).collect();
        let r = self
            .client
            .call_method(
                Some(self.dest.as_str()),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "Notify",
                &(
                    "app", replaces, "icon", summary, body, actions, hints, timeout,
                ),
            )
            .await
            .unwrap();
        r.body().deserialize().unwrap()
    }

    async fn call<B: serde::Serialize + zbus::zvariant::DynamicType>(
        &self,
        method: &str,
        body: &B,
    ) -> zbus::Message {
        self.client
            .call_method(
                Some(self.dest.as_str()),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                method,
                body,
            )
            .await
            .unwrap()
    }

    async fn sig(&mut self) -> String {
        tokio::time::timeout(Duration::from_secs(5), self.sigs.recv())
            .await
            .expect("signal timeout")
            .unwrap()
    }
}

fn urgency(u: u8) -> Hints {
    HashMap::from([("urgency", Value::U8(u))])
}

#[tokio::test]
async fn notify_creates_document() {
    let f = fixture(|_| {}).await;
    let init = f.rec.wait("initial", |_| true).await;
    assert_eq!(init["items"], serde_json::json!([]));
    let id = f
        .notify(0, "Hi", "body", &["default", "Open"], HashMap::new(), -1)
        .await;
    assert_eq!(id, 1);
    let d = f
        .rec
        .wait("item", |d| d["items"].as_array().unwrap().len() == 1)
        .await;
    assert_no_null(&d);
    assert_eq!(d["toasts"], serde_json::json!([1]));
    assert_eq!(d["unread"], 1);
    assert_eq!(d["items"][0]["summary"], "Hi");
    assert_eq!(d["items"][0]["actions"][0]["label"], "Open");
    assert_eq!(d["items"][0]["urgency"], "normal");
    f.cmds.mark_read(1);
    let d = f.rec.wait("read", |d| d["unread"] == 0).await;
    assert_eq!(
        d["toasts"],
        serde_json::json!([1]),
        "read does not hide toast"
    );
}

#[tokio::test]
async fn replaces_id_updates_in_place() {
    let f = fixture(|_| {}).await;
    let a = f.notify(0, "one", "", &[], HashMap::new(), 0).await;
    let b = f.notify(a, "two", "", &[], HashMap::new(), 0).await;
    assert_eq!(a, b);
    let d = f
        .rec
        .wait("replaced", |d| d["items"][0]["summary"] == "two")
        .await;
    assert_eq!(d["items"].as_array().unwrap().len(), 1);
    let c = f.notify(0, "three", "", &[], HashMap::new(), 0).await;
    assert_ne!(c, a);
    let d = f
        .rec
        .wait("two items", |d| d["items"].as_array().unwrap().len() == 2)
        .await;
    assert_eq!(d["items"][0]["summary"], "three", "newest first");
}

#[tokio::test]
async fn expiry_via_deadline() {
    let mut f = fixture(|_| {}).await;
    let id = f.notify(0, "t", "", &[], HashMap::new(), 150).await;
    let d = f
        .rec
        .wait("toast", |d| d["toasts"] == serde_json::json!([id]))
        .await;
    assert!(d["items"][0]["expires_at"].is_u64());
    assert_eq!(f.sig().await, format!("closed:{id}:1"));
    let d = f
        .rec
        .wait("expired", |d| d["toasts"] == serde_json::json!([]))
        .await;
    assert_eq!(d["items"].as_array().unwrap().len(), 1, "stays in history");
    assert!(d["items"][0].get("expires_at").is_none());
}

#[tokio::test]
async fn default_timeout_from_config_and_zero_never() {
    let mut f = fixture(|c| c.timeout_normal_ms = 100).await;
    let never = f.notify(0, "never", "", &[], HashMap::new(), 0).await;
    let dflt = f.notify(0, "dflt", "", &[], HashMap::new(), -1).await;
    assert_eq!(f.sig().await, format!("closed:{dflt}:1"));
    let d = f
        .rec
        .wait("only never", |d| d["toasts"] == serde_json::json!([never]))
        .await;
    assert_no_null(&d);
}

#[tokio::test]
async fn dnd_stores_silently_critical_ignores() {
    let f = fixture(|c| c.dnd = true).await;
    let quiet = f.notify(0, "q", "", &[], HashMap::new(), 0).await;
    let loud = f.notify(0, "c", "", &[], urgency(2), 0).await;
    let d = f
        .rec
        .wait("both", |d| d["items"].as_array().unwrap().len() == 2)
        .await;
    assert_eq!(d["dnd"], true);
    assert_eq!(d["toasts"], serde_json::json!([loud]));
    assert!(
        d["items"]
            .as_array()
            .unwrap()
            .iter()
            .any(|i| i["id"] == quiet)
    );
    f.cmds.set_dnd(false);
    f.rec.wait("dnd off", |d| d["dnd"] == false).await;
}

#[tokio::test]
async fn actions_round_trip_with_signals() {
    let mut f = fixture(|_| {}).await;
    let id = f
        .notify(
            0,
            "a",
            "",
            &["default", "Open", "x", "X"],
            HashMap::new(),
            0,
        )
        .await;
    f.cmds.invoke_action(id, "bogus").await;
    f.cmds.invoke_action(id, "x").await;
    assert_eq!(f.sig().await, format!("action:{id}:x"));
    assert_eq!(f.sig().await, format!("closed:{id}:2"));
    let d = f
        .rec
        .wait("gone", |d| d["items"].as_array().unwrap().is_empty())
        .await;
    assert_eq!(d["unread"], 0);

    // Resident: action fires, toast hides, history keeps it, no Closed signal.
    let r = f
        .notify(
            0,
            "r",
            "",
            &["k", "K"],
            HashMap::from([("resident", Value::Bool(true))]),
            0,
        )
        .await;
    f.cmds.invoke_action(r, "k").await;
    assert_eq!(f.sig().await, format!("action:{r}:k"));
    let d = f
        .rec
        .wait("resident kept", |d| d["toasts"] == serde_json::json!([]))
        .await;
    assert_eq!(d["items"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn inline_reply_signal() {
    let mut f = fixture(|_| {}).await;
    let id = f.notify(0, "m", "", &[], HashMap::new(), 0).await;
    f.cmds.reply(id, "hello").await;
    assert_eq!(f.sig().await, format!("replied:{id}:hello"));
    assert_eq!(f.sig().await, format!("closed:{id}:2"));
}

#[tokio::test]
async fn close_reasons() {
    let mut f = fixture(|_| {}).await;
    let a = f.notify(0, "a", "", &[], HashMap::new(), 0).await;
    let b = f.notify(0, "b", "", &[], HashMap::new(), 0).await;
    let c = f.notify(0, "c", "", &[], HashMap::new(), 0).await;
    f.call("CloseNotification", &(a,)).await;
    assert_eq!(f.sig().await, format!("closed:{a}:3"));
    f.cmds.dismiss(b).await;
    assert_eq!(f.sig().await, format!("closed:{b}:2"));
    f.cmds.dismiss_all().await;
    assert_eq!(f.sig().await, format!("closed:{c}:2"));
    f.rec
        .wait("empty", |d| d["items"].as_array().unwrap().is_empty())
        .await;
    // Unknown id: no signal, no panic.
    f.cmds.dismiss(999).await;
}

#[tokio::test]
async fn markup_is_sanitised() {
    let f = fixture(|_| {}).await;
    f.notify(
        0,
        "s",
        "<b>ok</b><script>steal()</script><img src=\"file:///etc/passwd\"/> <a href=\"javascript:x\">l</a>",
        &[],
        HashMap::new(),
        0,
    )
    .await;
    let d = f
        .rec
        .wait("item", |d| !d["items"].as_array().unwrap().is_empty())
        .await;
    assert_eq!(d["items"][0]["body"], "<b>ok</b> l");
}

#[tokio::test]
async fn image_hint_is_cached_as_file() {
    let f = fixture(|_| {}).await;
    let px: Vec<u8> = (0..2 * 2).flat_map(|i| [i * 10, 0, 255, 255]).collect();
    let img = StructureBuilder::new()
        .add_field(2i32)
        .add_field(2i32)
        .add_field(8i32)
        .add_field(true)
        .add_field(8i32)
        .add_field(4i32)
        .add_field(px)
        .build()
        .unwrap();
    f.notify(
        0,
        "pic",
        "",
        &[],
        HashMap::from([("image-data", Value::Structure(img))]),
        0,
    )
    .await;
    let d = f
        .rec
        .wait("image", |d| d["items"][0].get("image").is_some())
        .await;
    let path = d["items"][0]["image"].as_str().unwrap();
    assert!(path.starts_with(f.cache.path().to_str().unwrap()));
    let bytes = std::fs::read(path).unwrap();
    assert_eq!(&bytes[1..4], b"PNG");
    assert!(
        !d.to_string().contains("255, 255"),
        "no pixel data in the doc"
    );
}

#[tokio::test]
async fn history_is_bounded() {
    let f = fixture(|c| c.history_max = 3).await;
    for i in 0..5 {
        f.notify(0, &format!("n{i}"), "", &[], HashMap::new(), 0)
            .await;
    }
    let d = f
        .rec
        .wait("bounded", |d| d["items"][0]["summary"] == "n4")
        .await;
    assert_eq!(d["items"].as_array().unwrap().len(), 3);
}

#[tokio::test]
async fn capabilities_and_server_information() {
    let f = fixture(|_| {}).await;
    let caps: Vec<String> = f
        .call("GetCapabilities", &())
        .await
        .body()
        .deserialize()
        .unwrap();
    for c in [
        "body",
        "body-markup",
        "actions",
        "icon-static",
        "persistence",
    ] {
        assert!(caps.iter().any(|x| x == c), "missing {c}");
    }
    let (name, _vendor, _ver, spec): (String, String, String, String) = f
        .call("GetServerInformation", &())
        .await
        .body()
        .deserialize()
        .unwrap();
    assert_eq!(name, "kurashi");
    assert_eq!(spec, "1.2");
}

#[tokio::test]
async fn claims_name_only_when_told() {
    // Private bus only: claim_name = true here never touches the user's session.
    let bus = TestBus::start();
    let conn = bus.conn().await;
    let cache = tempfile::tempdir().unwrap();
    let dbus = zbus::fdo::DBusProxy::new(&conn).await.unwrap();
    let name = zbus::names::BusName::try_from("org.freedesktop.Notifications").unwrap();

    let mut cfg = NotifyConfig::new(cache.path().into());
    cfg.claim_name = false;
    let (h, _c) = Server::serve(conn.clone(), Rec::new(), cfg).await.unwrap();
    assert!(!dbus.name_has_owner(name.clone()).await.unwrap());
    drop(h);

    let conn2 = bus.conn().await;
    let dbus2 = zbus::fdo::DBusProxy::new(&conn2).await.unwrap();
    let cfg = NotifyConfig::new(cache.path().into());
    let (_h, _c) = Server::serve(conn2, Rec::new(), cfg).await.unwrap();
    assert!(dbus2.name_has_owner(name).await.unwrap());
}
