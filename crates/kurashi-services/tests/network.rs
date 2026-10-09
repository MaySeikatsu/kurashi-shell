mod common;

use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::network;
use zbus::zvariant::OwnedObjectPath;

struct Nm {
    state: u32,
    wifi: bool,
    primary: String,
}
#[zbus::interface(name = "org.freedesktop.NetworkManager")]
impl Nm {
    #[zbus(property)]
    fn state(&self) -> u32 {
        self.state
    }
    #[zbus(property)]
    fn wireless_enabled(&self) -> bool {
        self.wifi
    }
    #[zbus(property)]
    fn set_wireless_enabled(&mut self, v: bool) {
        self.wifi = v;
    }
    #[zbus(property)]
    fn primary_connection(&self) -> OwnedObjectPath {
        OwnedObjectPath::try_from(self.primary.as_str()).unwrap()
    }
}

struct Active;
#[zbus::interface(name = "org.freedesktop.NetworkManager.Connection.Active")]
impl Active {
    #[zbus(property, name = "Type")]
    fn kind(&self) -> String {
        "802-11-wireless".into()
    }
    #[zbus(property)]
    fn id(&self) -> String {
        "home-wifi".into()
    }
    #[zbus(property)]
    fn devices(&self) -> Vec<OwnedObjectPath> {
        vec![OwnedObjectPath::try_from("/org/freedesktop/NetworkManager/Devices/1").unwrap()]
    }
}

struct Wireless;
#[zbus::interface(name = "org.freedesktop.NetworkManager.Device.Wireless")]
impl Wireless {
    #[zbus(property)]
    fn active_access_point(&self) -> OwnedObjectPath {
        OwnedObjectPath::try_from("/org/freedesktop/NetworkManager/AccessPoint/1").unwrap()
    }
}

struct Ap {
    strength: u8,
}
#[zbus::interface(name = "org.freedesktop.NetworkManager.AccessPoint")]
impl Ap {
    #[zbus(property)]
    fn strength(&self) -> u8 {
        self.strength
    }
}

const NM: &str = "/org/freedesktop/NetworkManager";
const AP: &str = "/org/freedesktop/NetworkManager/AccessPoint/1";

#[tokio::test]
async fn network_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    let (handle, cmds) = network::start(bus.conn().await, rec.clone()).await.unwrap();
    let d = rec.wait("absent", |_| true).await;
    assert_eq!(
        d,
        serde_json::json!({"state": "unavailable", "wifi_enabled": false})
    );

    let srv = bus.server("org.freedesktop.NetworkManager").await;
    let os = srv.object_server();
    os.at(
        NM,
        Nm {
            state: 70,
            wifi: true,
            primary: "/org/freedesktop/NetworkManager/ActiveConnection/1".into(),
        },
    )
    .await
    .unwrap();
    os.at("/org/freedesktop/NetworkManager/ActiveConnection/1", Active)
        .await
        .unwrap();
    os.at("/org/freedesktop/NetworkManager/Devices/1", Wireless)
        .await
        .unwrap();
    os.at(AP, Ap { strength: 60 }).await.unwrap();
    let nm = os.interface::<_, Nm>(NM).await.unwrap();
    nm.get()
        .await
        .state_changed(nm.signal_emitter())
        .await
        .unwrap();

    let d = rec.wait("connected", |d| d["state"] == "connected").await;
    assert_eq!(
        d["primary"],
        serde_json::json!({"kind": "wifi", "name": "home-wifi", "strength": 60})
    );
    assert_eq!(d["wifi_enabled"], true);
    assert_no_null(&d);

    // AP strength change (different object, same namespace).
    let ap = os.interface::<_, Ap>(AP).await.unwrap();
    ap.get_mut().await.strength = 33;
    ap.get()
        .await
        .strength_changed(ap.signal_emitter())
        .await
        .unwrap();
    rec.wait("strength", |d| d["primary"]["strength"] == 33)
        .await;

    // Command: wifi off goes through the property setter.
    cmds.set_wifi_enabled(false).await.unwrap();
    rec.wait("wifi off", |d| d["wifi_enabled"] == false).await;

    // No primary connection -> field absent.
    nm.get_mut().await.primary = "/".into();
    nm.get_mut().await.state = 20;
    nm.get()
        .await
        .primary_connection_changed(nm.signal_emitter())
        .await
        .unwrap();
    nm.get()
        .await
        .state_changed(nm.signal_emitter())
        .await
        .unwrap();
    let d = rec
        .wait("disconnected", |d| d["state"] == "disconnected")
        .await;
    assert!(d.get("primary").is_none());

    drop((nm, ap, os));
    drop(srv);
    rec.wait("owner gone", |d| d["state"] == "unavailable")
        .await;

    drop(handle);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    let srv = bus.server("org.freedesktop.NetworkManager").await;
    srv.object_server()
        .at(
            NM,
            Nm {
                state: 70,
                wifi: true,
                primary: "/".into(),
            },
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}
