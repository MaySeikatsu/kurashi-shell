mod common;

use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::bluetooth;
use serde_json::{Value, json};
use zbus::Connection;
use zbus::fdo::ObjectManager;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::OwnedObjectPath;

const ADAPTER: &str = "/org/bluez/hci0";
const HEADSET: &str = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_01";
const HEADSET_ADDR: &str = "AA:BB:CC:DD:EE:01";
const SPEAKER: &str = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02";
const SPEAKER_ADDR: &str = "AA:BB:CC:DD:EE:02";

/// Fake org.bluez.Adapter1: Powered is writable (Properties.Set); scans are methods that announce
/// the Discovering change the way BlueZ does.
struct Adapter {
    powered: bool,
    discovering: bool,
}

#[zbus::interface(name = "org.bluez.Adapter1")]
impl Adapter {
    #[zbus(property)]
    fn powered(&self) -> bool {
        self.powered
    }
    #[zbus(property)]
    fn set_powered(&mut self, on: bool) {
        self.powered = on;
    }
    #[zbus(property)]
    fn discovering(&self) -> bool {
        self.discovering
    }
    async fn start_discovery(
        &mut self,
        #[zbus(signal_emitter)] ctx: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        self.discovering = true;
        self.discovering_changed(&ctx).await?;
        Ok(())
    }
    async fn stop_discovery(
        &mut self,
        #[zbus(signal_emitter)] ctx: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        self.discovering = false;
        self.discovering_changed(&ctx).await?;
        Ok(())
    }
}

/// Fake org.bluez.Device1. Connect/Disconnect are methods that announce the Connected change.
struct Device {
    address: String,
    alias: String,
    paired: bool,
    connected: bool,
}

#[zbus::interface(name = "org.bluez.Device1")]
impl Device {
    #[zbus(property)]
    fn adapter(&self) -> OwnedObjectPath {
        OwnedObjectPath::try_from(ADAPTER).unwrap()
    }
    #[zbus(property)]
    fn address(&self) -> String {
        self.address.clone()
    }
    #[zbus(property)]
    fn alias(&self) -> String {
        self.alias.clone()
    }
    #[zbus(property)]
    fn icon(&self) -> String {
        "audio-headset".into()
    }
    #[zbus(property)]
    fn paired(&self) -> bool {
        self.paired
    }
    #[zbus(property)]
    fn connected(&self) -> bool {
        self.connected
    }
    async fn connect(
        &mut self,
        #[zbus(signal_emitter)] ctx: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        self.connected = true;
        self.connected_changed(&ctx).await?;
        Ok(())
    }
    async fn disconnect(
        &mut self,
        #[zbus(signal_emitter)] ctx: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        self.connected = false;
        self.connected_changed(&ctx).await?;
        Ok(())
    }
}

struct Battery(u8);

#[zbus::interface(name = "org.bluez.Battery1")]
impl Battery {
    #[zbus(property)]
    fn percentage(&self) -> u8 {
        self.0
    }
}

/// A fake BlueZ. The ObjectManager goes up before the name, as on a real BlueZ start, and every
/// `at` under it announces InterfacesAdded by itself.
async fn serve_bluez(bus: &TestBus) -> Connection {
    let conn = bus.conn().await;
    conn.object_server().at("/", ObjectManager).await.unwrap();
    conn.request_name("org.bluez").await.unwrap();
    conn
}

fn find<'a>(doc: &'a Value, address: &str) -> Option<&'a Value> {
    doc["devices"]
        .as_array()?
        .iter()
        .find(|d| d["address"] == address)
}

#[tokio::test]
async fn bluetooth_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = bluetooth::start(bus.conn().await, rec.clone())
        .await
        .unwrap();
    // No BlueZ on the bus: the document says so, and commands fail rather than starting it.
    assert_eq!(
        rec.wait("absent", |_| true).await,
        json!({"available": false})
    );
    assert!(cmds.set_powered(true).await.is_err());

    let srv = serve_bluez(&bus).await;
    let os = srv.object_server();
    // Adapter and devices appear: InterfacesAdded for each, the service reads them from the cache.
    os.at(
        ADAPTER,
        Adapter {
            powered: true,
            discovering: false,
        },
    )
    .await
    .unwrap();
    os.at(
        SPEAKER,
        Device {
            address: SPEAKER_ADDR.into(),
            alias: "Kitchen".into(),
            paired: true,
            connected: false,
        },
    )
    .await
    .unwrap();
    os.at(
        HEADSET,
        Device {
            address: HEADSET_ADDR.into(),
            alias: "WH-1000XM4".into(),
            paired: true,
            connected: false,
        },
    )
    .await
    .unwrap();
    let d = rec
        .wait("two devices", |d| {
            d["devices"].as_array().is_some_and(|a| a.len() == 2)
        })
        .await;
    assert_eq!(
        d,
        json!({
            "available": true,
            "powered": true,
            "discovering": false,
            "devices": [
                {"address": SPEAKER_ADDR, "name": "Kitchen", "icon": "audio-headset",
                 "paired": true, "connected": false},
                {"address": HEADSET_ADDR, "name": "WH-1000XM4", "icon": "audio-headset",
                 "paired": true, "connected": false},
            ],
        })
    );
    assert_no_null(&d);

    // Battery1 on the headset arrives as its own InterfacesAdded.
    os.at(HEADSET, Battery(80)).await.unwrap();
    rec.wait("battery", |d| {
        find(d, HEADSET_ADDR).is_some_and(|h| h["battery"] == 80)
    })
    .await;

    // BlueZ-side Connected change: PropertiesChanged updates the cache, and the connected device
    // sorts first.
    let headset = os.interface::<_, Device>(HEADSET).await.unwrap();
    headset.get_mut().await.connected = true;
    headset
        .get()
        .await
        .connected_changed(headset.signal_emitter())
        .await
        .unwrap();
    let d = rec
        .wait("connected", |d| {
            d["devices"][0]["address"] == HEADSET_ADDR && d["devices"][0]["connected"] == true
        })
        .await;
    assert_no_null(&d);

    // Command path: disconnect reaches the fake, and the document follows BlueZ's signal.
    cmds.disconnect(HEADSET_ADDR).await.unwrap();
    rec.wait("disconnected", |d| {
        find(d, HEADSET_ADDR).is_some_and(|h| h["connected"] == false)
    })
    .await;
    assert!(
        !headset.get().await.connected,
        "Disconnect reached the fake"
    );

    // set_powered goes through Properties.Set and reaches the fake.
    cmds.set_powered(false).await.unwrap();
    rec.wait("powered off", |d| d["powered"] == false).await;
    let adapter = os.interface::<_, Adapter>(ADAPTER).await.unwrap();
    assert!(
        !adapter.get().await.powered,
        "Properties.Set reached the fake"
    );

    // A scan we start shows up as discovering.
    cmds.start_discovery().await.unwrap();
    rec.wait("scanning", |d| d["discovering"] == true).await;
    assert!(
        adapter.get().await.discovering,
        "StartDiscovery reached the fake"
    );

    // Device removal (and its battery) removes it from the document.
    os.remove::<Device, _>(SPEAKER).await.unwrap();
    let d = rec
        .wait("speaker removed", |d| find(d, SPEAKER_ADDR).is_none())
        .await;
    assert_no_null(&d);

    // Dropping the handle stops the scan we own, and the sink goes quiet.
    drop(handle);
    for _ in 0..200 {
        if !adapter.get().await.discovering {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert!(
        !adapter.get().await.discovering,
        "scan stopped with the handle"
    );
    assert!(
        cmds.start_discovery().await.is_err(),
        "no scan can start after the handle is gone"
    );
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    headset.get_mut().await.paired = false;
    headset
        .get()
        .await
        .paired_changed(headset.signal_emitter())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}

#[tokio::test]
async fn bluez_restart_resets_document() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, _cmds) = bluetooth::start(bus.conn().await, rec.clone())
        .await
        .unwrap();

    let srv = serve_bluez(&bus).await;
    srv.object_server()
        .at(
            ADAPTER,
            Adapter {
                powered: true,
                discovering: false,
            },
        )
        .await
        .unwrap();
    srv.object_server()
        .at(
            HEADSET,
            Device {
                address: HEADSET_ADDR.into(),
                alias: "WH-1000XM4".into(),
                paired: true,
                connected: false,
            },
        )
        .await
        .unwrap();
    rec.wait("device", |d| find(d, HEADSET_ADDR).is_some())
        .await;

    // BlueZ exits: its tree goes with it.
    drop(srv);
    rec.wait("gone", |d| d == &json!({"available": false}))
        .await;

    // BlueZ comes back with a powered-off adapter and nothing paired: the document follows.
    let srv = serve_bluez(&bus).await;
    srv.object_server()
        .at(
            ADAPTER,
            Adapter {
                powered: false,
                discovering: false,
            },
        )
        .await
        .unwrap();
    rec.wait("back", |d| {
        d == &json!({"available": true, "powered": false, "discovering": false, "devices": []})
    })
    .await;
    drop(handle);
}
