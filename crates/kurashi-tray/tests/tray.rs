mod common;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_tray::{Commands, ServiceHandle};
use serde_json::{Value, json};
use zbus::names::{BusName, InterfaceName};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value as ZValue};
use zbus::{Connection, fdo};

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM_IFACE: &str = "org.kde.StatusNotifierItem";
const ITEM_PATH: &str = "/StatusNotifierItem";
const MENU_PATH: &str = "/MenuBar";

type Calls = Arc<Mutex<Vec<String>>>;
type MenuEvents = Arc<Mutex<Vec<(i32, String)>>>;
/// `a(iiay)` pixmap, and the `(sa(iiay)ss)` tooltip and `(ia{sv}av)` layout the fakes return.
type Pixmap = (i32, i32, Vec<u8>);
type ToolTip = (String, Vec<Pixmap>, String, String);
type Layout = (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>);

/// The StatusNotifierItem interface of a fake item.
#[derive(Clone)]
struct ItemIface {
    title: Arc<Mutex<String>>,
    calls: Calls,
}

#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl ItemIface {
    #[zbus(property)]
    fn title(&self) -> String {
        self.title.lock().unwrap().clone()
    }
    #[zbus(property)]
    fn status(&self) -> String {
        "Active".into()
    }
    #[zbus(property)]
    fn icon_name(&self) -> String {
        "network-wireless".into()
    }
    /// 2x2 opaque green, ARGB32 in network byte order.
    #[zbus(property)]
    fn icon_pixmap(&self) -> Vec<Pixmap> {
        vec![(2, 2, [255, 0, 255, 0].repeat(4))]
    }
    #[zbus(property)]
    fn tool_tip(&self) -> ToolTip {
        (String::new(), vec![], "Wi-Fi".into(), "connected".into())
    }
    #[zbus(property)]
    fn menu(&self) -> OwnedObjectPath {
        OwnedObjectPath::try_from(MENU_PATH).unwrap()
    }
    fn activate(&self, x: i32, y: i32) {
        self.calls.lock().unwrap().push(format!("activate {x} {y}"));
    }
    fn secondary_activate(&self, x: i32, y: i32) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("secondary {x} {y}"));
    }
    fn scroll(&self, delta: i32, orientation: String) {
        self.calls
            .lock()
            .unwrap()
            .push(format!("scroll {delta} {orientation}"));
    }
}

/// A dbusmenu with one hidden entry, one separator, a toggle and a submenu.
#[derive(Clone)]
struct MenuIface {
    events: MenuEvents,
}

#[zbus::interface(name = "com.canonical.dbusmenu")]
impl MenuIface {
    #[zbus(property)]
    fn version(&self) -> u32 {
        3
    }
    fn about_to_show(&self, _id: i32) -> bool {
        false
    }
    fn get_layout(&self, _parent: i32, _depth: i32, _names: Vec<String>) -> (u32, Layout) {
        let kids = vec![
            node(
                1,
                vec![("label", val("_Open")), ("enabled", val(true))],
                vec![],
            ),
            node(2, vec![("type", val("separator"))], vec![]),
            node(
                3,
                vec![
                    ("label", val("Quit")),
                    ("icon-name", val("application-exit")),
                ],
                vec![],
            ),
            node(
                4,
                vec![("label", val("Secret")), ("visible", val(false))],
                vec![],
            ),
            node(
                5,
                vec![
                    ("label", val("Wi_fi")),
                    ("toggle-type", val("checkmark")),
                    ("toggle-state", val(1i32)),
                ],
                vec![],
            ),
            node(
                6,
                vec![("label", val("More"))],
                vec![node(7, vec![("label", val("Deep"))], vec![])],
            ),
        ];
        (7, (0, HashMap::new(), kids))
    }
    fn event(&self, id: i32, event_id: String, _data: OwnedValue, _timestamp: u32) {
        self.events.lock().unwrap().push((id, event_id));
    }
}

fn val<T: Into<ZValue<'static>>>(v: T) -> OwnedValue {
    let v: ZValue<'static> = v.into();
    OwnedValue::try_from(v).unwrap()
}

/// One dbusmenu entry: `(ia{sv}av)` wrapped in a variant, as `av` children are.
fn node(id: i32, props: Vec<(&str, OwnedValue)>, kids: Vec<OwnedValue>) -> OwnedValue {
    let props: HashMap<String, OwnedValue> =
        props.into_iter().map(|(k, v)| (k.to_owned(), v)).collect();
    OwnedValue::try_from(ZValue::from((id, props, kids))).unwrap()
}

/// A fake item on its own connection, with the handles a test needs to observe it.
struct Item {
    conn: Connection,
    title: Arc<Mutex<String>>,
    calls: Calls,
    menu_events: MenuEvents,
}

impl Item {
    async fn new(bus: &TestBus, title: &str) -> Self {
        let conn = bus.conn().await;
        let title = Arc::new(Mutex::new(title.to_owned()));
        let calls: Calls = Arc::default();
        let menu_events: MenuEvents = Arc::default();
        let server = conn.object_server();
        server
            .at(
                ITEM_PATH,
                ItemIface {
                    title: title.clone(),
                    calls: calls.clone(),
                },
            )
            .await
            .unwrap();
        server
            .at(
                MENU_PATH,
                MenuIface {
                    events: menu_events.clone(),
                },
            )
            .await
            .unwrap();
        Self {
            conn,
            title,
            calls,
            menu_events,
        }
    }

    /// The way real items do it: by object path, so the watcher takes the sender's name.
    async fn register(&self) {
        register(&self.conn, ITEM_PATH).await;
    }

    /// The registry id the tray publishes for a path-registered item.
    fn id(&self) -> String {
        format!("{}{ITEM_PATH}", self.conn.unique_name().unwrap())
    }

    async fn set_title(&self, title: &str) {
        *self.title.lock().unwrap() = title.to_owned();
        self.conn
            .emit_signal(None::<&str>, ITEM_PATH, ITEM_IFACE, "NewTitle", &())
            .await
            .unwrap();
    }
}

async fn register(conn: &Connection, service: &str) {
    conn.call_method(
        Some(WATCHER),
        WATCHER_PATH,
        Some(WATCHER),
        "RegisterStatusNotifierItem",
        &(service,),
    )
    .await
    .unwrap();
}

async fn start_tray(bus: &TestBus) -> (Arc<Rec>, ServiceHandle, Commands) {
    let rec = Rec::new();
    let (handle, cmds) = kurashi_tray::start(bus.conn().await, rec.clone())
        .await
        .unwrap();
    (rec, handle, cmds)
}

fn item_titled<'a>(doc: &'a Value, title: &str) -> Option<&'a Value> {
    doc["items"]
        .as_array()?
        .iter()
        .find(|i| i["title"] == title)
}

fn item_count(doc: &Value) -> usize {
    doc["items"].as_array().map_or(0, Vec::len)
}

async fn name_owner(conn: &Connection, name: &str) -> Option<String> {
    let proxy = fdo::DBusProxy::new(conn).await.unwrap();
    proxy
        .get_name_owner(BusName::try_from(name).unwrap())
        .await
        .ok()
        .map(|u| u.to_string())
}

async fn registered_items(client: &Connection) -> Vec<String> {
    let proxy = fdo::PropertiesProxy::builder(client)
        .destination(WATCHER)
        .unwrap()
        .path(WATCHER_PATH)
        .unwrap()
        .build()
        .await
        .unwrap();
    let v = proxy
        .get(
            InterfaceName::try_from(WATCHER).unwrap(),
            "RegisteredStatusNotifierItems",
        )
        .await
        .unwrap();
    Vec::<String>::try_from(v).unwrap()
}

/// Poll a condition for up to five seconds. The tray reacts to bus events, never to a timer, so
/// the wait belongs to the test only.
async fn until(what: &str, mut check: impl FnMut() -> bool) {
    for _ in 0..200 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("timed out waiting for {what}");
}

#[tokio::test]
async fn item_appears_updates_and_leaves() {
    let bus = TestBus::start();
    let client = bus.conn().await;
    let (rec, _handle, _cmds) = start_tray(&bus).await;
    rec.wait("watcher available", |d| d["available"] == true)
        .await;

    let wifi = Item::new(&bus, "Wi-Fi").await;
    wifi.register().await;
    let doc = rec
        .wait("Wi-Fi item", |d| item_titled(d, "Wi-Fi").is_some())
        .await;
    let it = item_titled(&doc, "Wi-Fi").unwrap();
    assert_eq!(it["id"], wifi.id());
    assert_eq!(it["status"], "Active");
    assert_eq!(it["icon_name"], "network-wireless");
    assert_eq!(it["has_menu"], true);
    assert_eq!(it["tooltip"], "Wi-Fi\nconnected");
    assert_eq!(it["icon_pixmap"]["w"], 2);
    assert!(
        it["icon_pixmap"]["png_base64"]
            .as_str()
            .unwrap()
            .starts_with("iVBORw0KGgo"),
        "icon is a PNG"
    );
    assert_no_null(&doc);

    // Registering the same item again changes nothing.
    wifi.register().await;

    // A registration by well-known name is keyed by that name.
    let named = Item::new(&bus, "Named").await;
    named.conn.request_name("org.test.Named").await.unwrap();
    register(&named.conn, "org.test.Named").await;
    rec.wait("named item", |d| item_titled(d, "Named").is_some())
        .await;
    let doc = rec.last().unwrap();
    assert_eq!(
        item_count(&doc),
        2,
        "duplicate registration was not deduped"
    );
    assert_eq!(
        item_titled(&doc, "Named").unwrap()["id"],
        "org.test.Named/StatusNotifierItem"
    );
    assert_eq!(
        registered_items(&client).await,
        vec![wifi.id(), "org.test.Named/StatusNotifierItem".to_owned()]
    );

    // NewTitle re-reads the item.
    wifi.set_title("Ethernet").await;
    rec.wait("retitled", |d| item_titled(d, "Ethernet").is_some())
        .await;

    // The item's connection goes away, and so does its entry.
    let _ = wifi.conn.close().await;
    rec.wait("Wi-Fi removed", |d| item_titled(d, "Ethernet").is_none())
        .await;
    assert_eq!(item_count(&rec.last().unwrap()), 1);
    assert_eq!(
        registered_items(&client).await,
        vec!["org.test.Named/StatusNotifierItem".to_owned()]
    );
}

#[tokio::test]
async fn commands_reach_the_item_and_its_menu() {
    let bus = TestBus::start();
    let (rec, _handle, cmds) = start_tray(&bus).await;
    let item = Item::new(&bus, "Wi-Fi").await;
    item.register().await;
    let doc = rec
        .wait("item", |d| item_titled(d, "Wi-Fi").is_some())
        .await;
    let id = item_titled(&doc, "Wi-Fi").unwrap()["id"]
        .as_str()
        .unwrap()
        .to_owned();

    cmds.activate(&id, 3, 4).await.unwrap();
    cmds.secondary_activate(&id, 5, 6).await.unwrap();
    cmds.scroll(&id, -1, "vertical").await.unwrap();
    assert!(cmds.scroll(&id, 1, "diagonal").await.is_err());
    // An unknown id is a no-op, not an error.
    cmds.activate("no-such-item", 0, 0).await.unwrap();
    let calls = item.calls.lock().unwrap().clone();
    assert_eq!(
        calls,
        vec![
            "activate 3 4".to_owned(),
            "secondary 5 6".to_owned(),
            "scroll -1 vertical".to_owned(),
        ]
    );

    let tree = cmds.menu(&id).await.unwrap();
    assert_eq!(
        tree,
        json!({
            "id": 0,
            "enabled": true,
            "children": [
                {"id": 1, "label": "Open", "enabled": true},
                {"id": 2, "separator": true, "enabled": true},
                {"id": 3, "label": "Quit", "enabled": true, "icon_name": "application-exit"},
                {"id": 5, "label": "Wifi", "enabled": true, "toggle": "checkmark", "checked": true},
                {"id": 6, "label": "More", "enabled": true,
                 "children": [{"id": 7, "label": "Deep", "enabled": true}]},
            ],
        })
    );

    cmds.menu_event(&id, 3).await.unwrap();
    let events = item.menu_events.lock().unwrap().clone();
    assert_eq!(events, vec![(3, "clicked".to_owned())]);
}

/// The watcher that already holds the name. It records the host registration and serves its list.
#[derive(Clone)]
struct ForeignWatcher {
    hosts: Arc<Mutex<Vec<String>>>,
    items: Arc<Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl ForeignWatcher {
    fn register_status_notifier_host(&self, service: String) {
        self.hosts.lock().unwrap().push(service);
    }
    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.lock().unwrap().clone()
    }
}

#[tokio::test]
async fn second_watcher_is_not_stolen() {
    let bus = TestBus::start();
    let foreign_conn = bus.server(WATCHER).await;
    let foreign = ForeignWatcher {
        hosts: Arc::default(),
        items: Arc::default(),
    };
    foreign_conn
        .object_server()
        .at(WATCHER_PATH, foreign.clone())
        .await
        .unwrap();
    let foreign_owner = foreign_conn.unique_name().unwrap().to_string();

    let (rec, _handle, _cmds) = start_tray(&bus).await;
    rec.wait("available as host", |d| d["available"] == true)
        .await;

    let client = bus.conn().await;
    assert_eq!(
        name_owner(&client, WATCHER).await.as_deref(),
        Some(foreign_owner.as_str()),
        "the tray must not steal the watcher name"
    );
    until("host registration", || {
        !foreign.hosts.lock().unwrap().is_empty()
    })
    .await;
    assert!(
        foreign.hosts.lock().unwrap()[0].starts_with("org.kde.StatusNotifierHost-"),
        "registered as a host"
    );

    // Items the watcher announces reach the tray, which never registers them itself.
    let item = Item::new(&bus, "Wi-Fi").await;
    let id = item.id();
    foreign_conn
        .emit_signal(
            None::<&str>,
            WATCHER_PATH,
            WATCHER,
            "StatusNotifierItemRegistered",
            &(id.as_str(),),
        )
        .await
        .unwrap();
    rec.wait("item via the foreign watcher", |d| {
        item_titled(d, "Wi-Fi").is_some()
    })
    .await;
    foreign_conn
        .emit_signal(
            None::<&str>,
            WATCHER_PATH,
            WATCHER,
            "StatusNotifierItemUnregistered",
            &(id.as_str(),),
        )
        .await
        .unwrap();
    rec.wait("item gone with the foreign watcher", |d| {
        item_titled(d, "Wi-Fi").is_none()
    })
    .await;
}

#[tokio::test]
async fn name_taken_over_by_a_new_owner_keeps_the_new_registration() {
    let bus = TestBus::start();
    let (rec, _handle, _cmds) = start_tray(&bus).await;
    rec.wait("watcher available", |d| d["available"] == true)
        .await;

    let old = Item::new(&bus, "Old").await;
    old.conn
        .request_name_with_flags(
            "org.test.Re",
            fdo::RequestNameFlags::AllowReplacement.into(),
        )
        .await
        .unwrap();
    register(&old.conn, "org.test.Re").await;
    rec.wait("old registration", |d| item_titled(d, "Old").is_some())
        .await;

    // The name moves to a second connection, which registers under the same id. Whichever of
    // the owner-change signal and the registration the tray sees first, the new one must stay.
    let new = Item::new(&bus, "New").await;
    new.conn
        .request_name_with_flags("org.test.Re", fdo::RequestNameFlags::ReplaceExisting.into())
        .await
        .unwrap();
    register(&new.conn, "org.test.Re").await;
    rec.wait("new registration replaces old", |d| {
        item_titled(d, "New").is_some() && item_titled(d, "Old").is_none()
    })
    .await;
    assert_eq!(item_count(&rec.last().unwrap()), 1);
}

#[tokio::test]
async fn dropping_the_tray_releases_the_watcher_name() {
    let bus = TestBus::start();
    let (rec, handle, _cmds) = start_tray(&bus).await;
    rec.wait("owner", |d| d["available"] == true).await;
    let client = bus.conn().await;
    assert!(name_owner(&client, WATCHER).await.is_some());

    drop(handle);
    for _ in 0..200 {
        if name_owner(&client, WATCHER).await.is_none() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the watcher name was not released");
}

#[tokio::test]
async fn dropped_watcher_passes_to_a_waiting_host() {
    let bus = TestBus::start();
    let (rec_a, handle_a, _) = start_tray(&bus).await;
    rec_a.wait("owner", |d| d["available"] == true).await;
    let (rec_b, _handle_b, _) = start_tray(&bus).await;
    rec_b.wait("host", |d| d["available"] == true).await;

    let client = bus.conn().await;
    let first = name_owner(&client, WATCHER)
        .await
        .expect("the name has an owner");
    drop(handle_a);
    let mut second = None;
    for _ in 0..200 {
        if let Some(o) = name_owner(&client, WATCHER).await.filter(|o| *o != first) {
            second = Some(o);
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert!(second.is_some(), "the waiting host did not take the name");

    // The new owner serves the watcher: items registered to the name reach its document.
    let item = Item::new(&bus, "Wi-Fi").await;
    item.register().await;
    rec_b
        .wait("item via the taken-over watcher", |d| {
            item_titled(d, "Wi-Fi").is_some()
        })
        .await;
}
