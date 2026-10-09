//! The quick settings pages' daemon side (W13): `svc.network.scan` and the `network.*` actions over
//! a private bus with a fake NetworkManager. Nothing here touches the user's session or system bus.

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use kurashid::actions::{ActionError, ActionRegistry};
use kurashid::hub::Hub;
use kurashid::services::ConnectFn;
use kurashid::wiring::{
    ARGS_INVALID, NETWORK_NEEDS_SECRET, NETWORK_NOT_FOUND, NETWORK_NOT_SAVED, NETWORK_REFUSED,
    SERVICE_NOT_RUNNING,
};
use serde_json::{Value, json};
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

const UNTIL: Duration = Duration::from_secs(10);
/// How often a test's subscription rescans: fast enough to count rescans in a second.
const SCAN_EVERY: Duration = Duration::from_millis(100);

/// Polls `ok` until it holds; the test fails when `UNTIL` runs out first.
async fn until(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + UNTIL;
    while !ok() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

/// A directory for one test's bus, removed when the test ends. Declared before the bus so it
/// outlives it.
struct Scratch(PathBuf);

impl Scratch {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("kurashid-pages-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Scratch(dir)
    }

    fn addr(&self) -> String {
        format!("unix:path={}", self.0.join("bus").display())
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// A session-type dbus-daemon on the scratch socket. Dropping it kills only this child.
struct PrivateBus(Child);

impl PrivateBus {
    fn start(scratch: &Scratch) -> Self {
        let socket = scratch.0.join("bus");
        let conf = scratch.0.join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type>
<listen>unix:path={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                socket.display()
            ),
        )
        .unwrap();
        let mut child = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut printed = String::new();
        BufReader::new(child.stdout.as_mut().unwrap())
            .read_line(&mut printed)
            .unwrap();
        assert!(
            printed.trim().starts_with(&scratch.addr()),
            "the daemon listens where the test expects: {printed}"
        );
        PrivateBus(child)
    }
}

impl Drop for PrivateBus {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// Opens the private bus at `addr` each time the service starts, as the daemon opens the system bus.
fn bus_at(addr: String) -> ConnectFn {
    Arc::new(move || {
        let addr = addr.clone();
        Box::pin(async move {
            zbus::connection::Builder::address(addr.as_str())?
                .build()
                .await
        })
    })
}

// ---- svc.network and svc.network.scan -----------------------------------------------------------

const NM: &str = "/org/freedesktop/NetworkManager";
const DEV: &str = "/org/freedesktop/NetworkManager/Devices/1";
const SETTINGS: &str = "/org/freedesktop/NetworkManager/Settings";
const ACTIVE: &str = "/org/freedesktop/NetworkManager/ActiveConnection/1";
const HOME_PROFILE: &str = "/org/freedesktop/NetworkManager/Settings/1";

/// Access points in range: (path, ssid, strength, secured). Two entries share "Home" (the second is
/// weaker); the first is the one the wifi device is connected to.
const APS: [(&str, &str, u8, bool); 4] = [
    (
        "/org/freedesktop/NetworkManager/AccessPoint/1",
        "Home",
        60,
        true,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/2",
        "Home",
        40,
        true,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/3",
        "Cafe",
        80,
        false,
    ),
    (
        "/org/freedesktop/NetworkManager/AccessPoint/4",
        "Office",
        30,
        true,
    ),
];
const ACTIVE_AP: &str = "/org/freedesktop/NetworkManager/AccessPoint/1";

/// What the fake NetworkManager holds. The test changes it, and its objects answer from it.
struct World {
    wifi: bool,
    wwan: bool,
    /// The primary connection's path, `/` when nothing is active.
    primary: String,
    /// Every rescan request the wifi device received.
    scans: usize,
    /// Each call that changed something, in order.
    log: Vec<String>,
    /// Every change is answered with polkit's refusal.
    refuse: bool,
}

type Shared = Arc<Mutex<World>>;

fn path(p: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(p).unwrap()
}

fn refused() -> zbus::fdo::Error {
    zbus::fdo::Error::AccessDenied("Not authorized to control networking.".into())
}

/// `org.freedesktop.NetworkManager`: the switches, the primary connection and the connect calls.
struct Root(Shared);

#[zbus::interface(name = "org.freedesktop.NetworkManager")]
impl Root {
    #[zbus(property)]
    fn state(&self) -> u32 {
        70
    }
    #[zbus(property)]
    fn wireless_enabled(&self) -> bool {
        self.0.lock().unwrap().wifi
    }
    #[zbus(property)]
    fn set_wireless_enabled(&mut self, on: bool) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.wifi = on;
        Ok(())
    }
    #[zbus(property)]
    fn wwan_enabled(&self) -> bool {
        self.0.lock().unwrap().wwan
    }
    #[zbus(property)]
    fn set_wwan_enabled(&mut self, on: bool) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.wwan = on;
        Ok(())
    }
    #[zbus(property)]
    fn primary_connection(&self) -> OwnedObjectPath {
        path(&self.0.lock().unwrap().primary)
    }
    #[zbus(property)]
    fn devices(&self) -> Vec<OwnedObjectPath> {
        vec![path(DEV)]
    }
    fn deactivate_connection(&self, active: OwnedObjectPath) -> zbus::fdo::Result<()> {
        let mut w = self.0.lock().unwrap();
        if w.refuse {
            return Err(refused());
        }
        w.log.push(format!("deactivate {active}"));
        w.primary = "/".into();
        Ok(())
    }
    fn activate_connection(
        &self,
        connection: OwnedObjectPath,
        _device: OwnedObjectPath,
        _specific: OwnedObjectPath,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        let mut w = self.0.lock().unwrap();
        w.log.push(format!("activate {connection}"));
        Ok(path(ACTIVE))
    }
}

/// The wifi device: its access points, its active one, and the rescan request.
struct Wireless(Shared);

#[zbus::interface(name = "org.freedesktop.NetworkManager.Device.Wireless")]
impl Wireless {
    #[zbus(property)]
    fn access_points(&self) -> Vec<OwnedObjectPath> {
        APS.iter().map(|ap| path(ap.0)).collect()
    }
    #[zbus(property)]
    fn active_access_point(&self) -> OwnedObjectPath {
        path(ACTIVE_AP)
    }
    fn request_scan(&self, _options: HashMap<String, zbus::zvariant::Value<'_>>) {
        self.0.lock().unwrap().scans += 1;
    }
}

/// The device itself: a wifi device.
struct Device;

#[zbus::interface(name = "org.freedesktop.NetworkManager.Device")]
impl Device {
    #[zbus(property)]
    fn device_type(&self) -> u32 {
        2
    }
    #[zbus(property)]
    fn interface(&self) -> String {
        "wlan0".into()
    }
}

/// One access point.
struct Ap {
    ssid: &'static str,
    strength: u8,
    secured: bool,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.AccessPoint")]
impl Ap {
    #[zbus(property)]
    fn ssid(&self) -> Vec<u8> {
        self.ssid.as_bytes().to_vec()
    }
    #[zbus(property)]
    fn strength(&self) -> u8 {
        self.strength
    }
    #[zbus(property)]
    fn flags(&self) -> u32 {
        u32::from(self.secured)
    }
    #[zbus(property)]
    fn wpa_flags(&self) -> u32 {
        0
    }
    #[zbus(property)]
    fn rsn_flags(&self) -> u32 {
        0
    }
}

/// `Settings`: the saved profiles.
struct SettingsRoot;

#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings")]
impl SettingsRoot {
    fn list_connections(&self) -> Vec<OwnedObjectPath> {
        vec![path(HOME_PROFILE)]
    }
}

/// A saved wifi profile for `ssid`.
struct Profile {
    ssid: &'static str,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings.Connection")]
impl Profile {
    fn get_settings(&self) -> HashMap<String, HashMap<String, OwnedValue>> {
        let value = |v: zbus::zvariant::Value<'_>| OwnedValue::try_from(v).unwrap();
        let connection = HashMap::from([("type".to_string(), value("802-11-wireless".into()))]);
        let wifi = HashMap::from([(
            "ssid".to_string(),
            value(self.ssid.as_bytes().to_vec().into()),
        )]);
        HashMap::from([
            ("connection".to_string(), connection),
            ("802-11-wireless".to_string(), wifi),
        ])
    }
}

/// Serves the fake NetworkManager on `addr` and returns its connection (keep it alive).
async fn serve_nm(addr: &str, world: Shared) -> Connection {
    let conn = zbus::connection::Builder::address(addr)
        .unwrap()
        .build()
        .await
        .unwrap();
    conn.request_name("org.freedesktop.NetworkManager")
        .await
        .unwrap();
    let os = conn.object_server();
    os.at(NM, Root(world.clone())).await.unwrap();
    os.at(DEV, Device).await.unwrap();
    os.at(DEV, Wireless(world.clone())).await.unwrap();
    for (p, ssid, strength, secured) in APS {
        os.at(
            p,
            Ap {
                ssid,
                strength,
                secured,
            },
        )
        .await
        .unwrap();
    }
    os.at(SETTINGS, SettingsRoot).await.unwrap();
    os.at(HOME_PROFILE, Profile { ssid: "Home" }).await.unwrap();
    conn
}

fn fresh_world() -> Shared {
    Arc::new(Mutex::new(World {
        wifi: true,
        wwan: true,
        primary: ACTIVE.into(),
        scans: 0,
        log: Vec::new(),
        refuse: false,
    }))
}

fn networks(hub: &Hub) -> Value {
    hub.snapshot("svc.network.scan").unwrap().1["networks"].clone()
}

#[tokio::test]
async fn scan_lists_each_network_once_and_rescans_only_while_subscribed() {
    let scratch = Scratch::new("scan");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let _nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);
    let scans = || world.lock().unwrap().scans;

    // Not subscribed: nothing lists, nothing scans.
    tokio::time::sleep(Duration::from_millis(350)).await;
    assert_eq!(scans(), 0, "scanned without a subscriber");
    assert_eq!(hub.snapshot("svc.network.scan").unwrap().1, json!({}));

    hub.subscribe("svc.network.scan").unwrap();
    until("the networks in range", || networks(&hub).is_array()).await;
    // One row per SSID (its strongest access point), the active one first, then by strength.
    assert_eq!(
        networks(&hub),
        json!([
            {"ssid": "Home", "strength": 60, "secure": true, "known": true, "active": true},
            {"ssid": "Cafe", "strength": 80, "secure": false, "known": false, "active": false},
            {"ssid": "Office", "strength": 30, "secure": true, "known": false, "active": false},
        ])
    );
    until("several rescans", || scans() >= 3).await;

    // Wi-Fi switched off: the list is not claimed, and the reason says why.
    world.lock().unwrap().wifi = false;
    until("the wifi-off reason", || {
        hub.snapshot("svc.network.scan").unwrap().1["reason"] == "error.network.wifi_off"
    })
    .await;
    assert_eq!(
        hub.snapshot("svc.network.scan").unwrap().1,
        json!({"available": false, "reason": "error.network.wifi_off"})
    );
    world.lock().unwrap().wifi = true;

    // Last unsubscribe: the scans stop with the service.
    hub.unsubscribe("svc.network.scan");
    let at_stop = scans();
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(scans(), at_stop, "rescans after the last unsubscribe");
}

#[tokio::test]
async fn connect_joins_saved_networks_and_says_why_it_cannot_join_the_rest() {
    let scratch = Scratch::new("connect");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let _nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);

    // Not subscribed: refused as not running, and nothing starts.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Home"}))
            .await,
        Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
    );

    hub.subscribe("svc.network").unwrap();
    until("NetworkManager's state", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "connected"
    })
    .await;

    // A saved network joins; the document follows NetworkManager, not this call.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Home"}))
            .await,
        Ok(None)
    );
    assert_eq!(
        world.lock().unwrap().log,
        vec![format!("activate {HOME_PROFILE}")]
    );

    // Refused, each with its key: secured but not saved, open but not saved, not in range.
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Office"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NEEDS_SECRET.into()))
    );
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Cafe"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NOT_SAVED.into()))
    );
    assert_eq!(
        actions
            .invoke("network.connect", json!({"ssid": "Nowhere"}))
            .await,
        Err(ActionError::Unavailable(NETWORK_NOT_FOUND.into()))
    );
    assert_eq!(
        actions.invoke("network.connect", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        actions.invoke("network.connect", json!({"ssid": ""})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );
    assert_eq!(
        world.lock().unwrap().log.len(),
        1,
        "a refused join changed nothing"
    );

    hub.unsubscribe("svc.network");
}

#[tokio::test]
async fn disconnect_and_airplane_follow_networkmanager_and_refusals_come_back_as_keys() {
    let scratch = Scratch::new("airplane");
    let _bus = PrivateBus::start(&scratch);
    let world = fresh_world();
    let nm = serve_nm(&scratch.addr(), world.clone()).await;
    let hub = Hub::new();
    let mut actions = ActionRegistry::default();
    kurashid::wiring::network_paced(&hub, &mut actions, bus_at(scratch.addr()), SCAN_EVERY);
    hub.subscribe("svc.network").unwrap();
    until("NetworkManager's state", || {
        hub.snapshot("svc.network").unwrap().1["state"] == "connected"
    })
    .await;
    assert_eq!(hub.snapshot("svc.network").unwrap().1["airplane"], false);

    // Disconnect deactivates the primary connection; NetworkManager then reports no primary.
    assert_eq!(
        actions.invoke("network.disconnect", json!({})).await,
        Ok(None)
    );
    assert_eq!(
        world.lock().unwrap().log,
        vec![format!("deactivate {ACTIVE}")]
    );
    until("no primary connection", || {
        hub.snapshot("svc.network")
            .unwrap()
            .1
            .get("primary")
            .is_none()
    })
    .await;

    // Airplane mode: wifi and mobile broadband off together, so the document reports it.
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": true}))
            .await,
        Ok(None)
    );
    until("airplane on", || {
        hub.snapshot("svc.network").unwrap().1["airplane"] == true
    })
    .await;
    assert_eq!(
        hub.snapshot("svc.network").unwrap().1["wifi_enabled"],
        false
    );
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": false}))
            .await,
        Ok(None)
    );
    until("airplane off", || {
        hub.snapshot("svc.network").unwrap().1["airplane"] == false
    })
    .await;
    assert_eq!(hub.snapshot("svc.network").unwrap().1["wifi_enabled"], true);

    // Polkit refuses: the key comes back and the document keeps what NetworkManager reports.
    world.lock().unwrap().refuse = true;
    assert_eq!(
        actions
            .invoke("network.airplane", json!({"on": true}))
            .await,
        Err(ActionError::Unavailable(NETWORK_REFUSED.into()))
    );
    assert_eq!(hub.snapshot("svc.network").unwrap().1["wifi_enabled"], true);
    assert_eq!(
        actions.invoke("network.airplane", json!({})).await,
        Err(ActionError::Invalid(ARGS_INVALID.into()))
    );

    hub.unsubscribe("svc.network");
    drop(nm);
}
