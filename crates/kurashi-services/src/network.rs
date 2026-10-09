//! `svc.network` — NetworkManager state, primary connection, wifi strength, airplane mode, and the
//! quick settings commands (connect, disconnect, airplane). `svc.network.scan` — the networks in
//! range, scanned only while something subscribes to it (`scan_loop`, Ma).

use std::collections::{BTreeMap, HashMap};
use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use futures_util::{Stream, StreamExt};
use serde_json::{Value, json};
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

use crate::util::{self, DocSink, Emitter, ServiceHandle};

const DEST: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const DEVICES_PREFIX: &str = "/org/freedesktop/NetworkManager/Devices/";
const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const SETTINGS_IF: &str = "org.freedesktop.NetworkManager.Settings";
const SETTING_IF: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const ACTIVE_IF: &str = "org.freedesktop.NetworkManager.Connection.Active";
const DEVICE_IF: &str = "org.freedesktop.NetworkManager.Device";
const WIRELESS_IF: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const AP_IF: &str = "org.freedesktop.NetworkManager.AccessPoint";
/// `NM_DEVICE_TYPE_WIFI`.
const DEVICE_TYPE_WIFI: u32 = 2;
/// `NM_802_11_AP_FLAGS_PRIVACY`: the access point advertises encryption.
const AP_FLAGS_PRIVACY: u32 = 0x1;

/// How often a subscribed scan asks NetworkManager for a fresh list (the GNOME cadence).
pub const SCAN_EVERY: Duration = Duration::from_secs(15);

/// Why NetworkManager did not take a radio or link change. The caller maps each to an i18n key
/// (PROTOCOL §8, `network.*`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WifiError {
    /// NetworkManager's polkit check, or the bus policy, said no.
    Refused,
    /// No NetworkManager on the bus, or the call failed for another reason.
    Unavailable,
}

/// Why `connect` did not start a connection. Only saved networks can be joined so far.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectError {
    Refused,
    Unavailable,
    /// Not saved and secured: joining needs a password the shell cannot ask for yet.
    NeedsSecret,
    /// Not saved and open: joinable in principle, not without a saved profile yet.
    NotSaved,
    /// Not saved and not in range.
    NotFound,
}

impl From<WifiError> for ConnectError {
    fn from(e: WifiError) -> Self {
        match e {
            WifiError::Refused => ConnectError::Refused,
            WifiError::Unavailable => ConnectError::Unavailable,
        }
    }
}

/// Error names a refused change comes back with: NetworkManager's own permission error, the polkit
/// one, and the bus policy's.
const REFUSED: [&str; 3] = [
    "org.freedesktop.NetworkManager.PermissionDenied",
    "org.freedesktop.PolicyKit1.Error.NotAuthorized",
    "org.freedesktop.DBus.Error.AccessDenied",
];

impl WifiError {
    fn of(err: &zbus::Error) -> Self {
        let refused = match err {
            zbus::Error::MethodError(name, _, _) => REFUSED.contains(&name.as_str()),
            zbus::Error::FDO(e) => matches!(**e, zbus::fdo::Error::AccessDenied(_)),
            _ => false,
        };
        if refused {
            WifiError::Refused
        } else {
            WifiError::Unavailable
        }
    }
}

#[derive(Clone)]
pub struct Commands {
    conn: Connection,
}

impl Commands {
    /// The document follows NetworkManager's PropertiesChanged, never this call (rule 2: no
    /// optimistic write), so a refused or failed write leaves the document as it was.
    pub async fn set_wifi_enabled(&self, on: bool) -> Result<(), WifiError> {
        self.set_nm_bool("WirelessEnabled", on).await
    }

    /// Airplane mode is the radio master switch: wifi and mobile broadband together. Turning it off
    /// turns both back on (the document's `airplane` is true only while both are off).
    pub async fn set_airplane(&self, on: bool) -> Result<(), WifiError> {
        self.set_nm_bool("WirelessEnabled", !on).await?;
        self.set_nm_bool("WwanEnabled", !on).await
    }

    /// Deactivates the primary connection. Nothing connected is not an error: the outcome asked for
    /// already holds.
    pub async fn disconnect(&self) -> Result<(), WifiError> {
        let nm = util::get_all(&self.conn, DEST, NM_PATH, DEST)
            .await
            .ok_or(WifiError::Unavailable)?;
        let Some(primary) = util::prop::<OwnedObjectPath>(&nm, "PrimaryConnection") else {
            return Err(WifiError::Unavailable);
        };
        if primary.as_str() == "/" {
            return Ok(());
        }
        util::call(
            &self.conn,
            DEST,
            NM_PATH,
            DEST,
            "DeactivateConnection",
            &(primary,),
        )
        .await
        .map(drop)
        .map_err(|e| {
            tracing::warn!(error = %e, "NetworkManager did not deactivate the connection");
            WifiError::of(&e)
        })
    }

    /// Joins a saved network on the first wifi device. Anything not saved is refused with the reason
    /// the shell can state (rule 2): secured needs a password, open is joinable but not yet, absent
    /// is not in range. NetworkManager's own progress shows in the document's `state`.
    pub async fn connect(&self, ssid: &str) -> Result<(), ConnectError> {
        let conn = &self.conn;
        let devices = wifi_devices(conn).await.ok_or(ConnectError::Unavailable)?;
        let device = devices.first().ok_or(ConnectError::Unavailable)?;
        let saved = wifi_profiles(conn)
            .await
            .into_iter()
            .find(|(_, s)| s.as_slice() == ssid.as_bytes());
        if let Some((profile, _)) = saved {
            let auto_ap = OwnedObjectPath::try_from("/").expect("root path");
            util::call(
                conn,
                DEST,
                NM_PATH,
                DEST,
                "ActivateConnection",
                &(profile, device.clone(), auto_ap),
            )
            .await
            .map(drop)
            .map_err(|e| {
                tracing::warn!(error = %e, "NetworkManager did not activate the profile");
                ConnectError::from(WifiError::of(&e))
            })?;
            return Ok(());
        }
        // Visible but not saved: any secured access point with this SSID decides it.
        let mut visible: Option<bool> = None;
        for dev in &devices {
            for ap in access_points(conn, dev).await {
                if ap.ssid == ssid.as_bytes() {
                    visible = Some(visible.unwrap_or(false) || ap.secure);
                }
            }
        }
        Err(match visible {
            Some(true) => ConnectError::NeedsSecret,
            Some(false) => ConnectError::NotSaved,
            None => ConnectError::NotFound,
        })
    }

    /// The document follows NetworkManager's PropertiesChanged, as for every write here.
    async fn set_nm_bool(&self, name: &str, on: bool) -> Result<(), WifiError> {
        let p = zbus::fdo::PropertiesProxy::builder(&self.conn)
            .destination(DEST)
            .and_then(|b| b.path(NM_PATH))
            .map_err(|_| WifiError::Unavailable)?
            .build()
            .await
            .map_err(|e| WifiError::of(&e))?;
        p.set(
            DEST.try_into().map_err(|_| WifiError::Unavailable)?,
            name,
            zbus::zvariant::Value::from(on),
        )
        .await
        .map_err(|e| {
            let e = zbus::Error::from(e);
            tracing::warn!(error = %e, property = name, "NetworkManager did not take the change");
            WifiError::of(&e)
        })
    }
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    // Namespace match so access-point strength changes (they live under the NM path) arrive too.
    let events = util::watch(
        &conn,
        vec![
            util::props_changed(NM_PATH)?,
            util::name_owner_changed(DEST)?,
        ],
    )
    .await?;
    let em = Emitter::new(sink);
    em.emit(read(&conn).await);
    let task = {
        let conn = conn.clone();
        tokio::spawn(async move {
            util::follow("network", &em, events, unavailable(), |_| read(&conn)).await;
        })
    };
    Ok((ServiceHandle::new(task), Commands { conn }))
}

/// `svc.network.scan` with the default cadence. Subscribing starts the scans, the last unsubscribe
/// stops them (the task and its match rules go with the handle).
pub async fn start_scan(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, ())> {
    start_scan_every(conn, sink, SCAN_EVERY).await
}

/// [`start_scan`] with the cadence injected (kurashid's tests run it fast on a private bus).
pub async fn start_scan_every(
    conn: Connection,
    sink: Arc<dyn DocSink>,
    every: Duration,
) -> Result<(ServiceHandle, ())> {
    let events = util::watch(
        &conn,
        vec![
            util::props_changed(NM_PATH)?,
            util::name_owner_changed(DEST)?,
        ],
    )
    .await?;
    let em = Emitter::new(sink);
    em.emit(scan_doc(&conn).await);
    let task = tokio::spawn(async move {
        let c = &conn;
        scan_loop(
            &em,
            events,
            every,
            refreshes,
            || request_scans(c),
            || scan_doc(c),
            scan_unavailable(),
        )
        .await;
    });
    Ok((ServiceHandle::new(task), ()))
}

/// The scan document's loop, generic over the bus so a paused-clock test can count the requests:
/// a scan request at once and then one per `every`, and a re-read whenever `wanted` says a bus
/// event changed what the document shows. The loop ends with its task.
async fn scan_loop<E, S, Req, ReqFut, Read, ReadFut>(
    em: &Emitter,
    mut events: S,
    every: Duration,
    wanted: impl Fn(&E) -> bool,
    mut request: Req,
    mut read: Read,
    unavailable: Value,
) where
    S: Stream<Item = zbus::Result<E>> + Unpin,
    Req: FnMut() -> ReqFut,
    ReqFut: Future<Output = ()>,
    Read: FnMut() -> ReadFut,
    ReadFut: Future<Output = Value>,
{
    let mut ticks = tokio::time::interval(every);
    ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tokio::select! {
            _ = ticks.tick() => {
                request().await;
                em.emit(read().await);
            }
            item = events.next() => match item {
                Some(Ok(event)) if wanted(&event) => em.emit(read().await),
                Some(Ok(_)) => {}
                _ => return util::ended("network.scan", em, unavailable),
            }
        }
    }
}

/// Bus events that can change the scan document: NetworkManager's own properties (wifi switch,
/// state), a wifi device's (its access points, its scan), and the bus name (NetworkManager came or
/// went). Access-point strength jitter is left to the next scan: re-reading per change would cost
/// dozens of calls each time.
fn refreshes(msg: &zbus::Message) -> bool {
    let header = msg.header();
    match header.path().map(|p| p.as_str()) {
        Some(p) => p == NM_PATH || p.starts_with(DEVICES_PREFIX) || p == "/org/freedesktop/DBus",
        None => false,
    }
}

fn state_name(s: u32) -> &'static str {
    match s {
        10 => "asleep",
        20 => "disconnected",
        30 => "disconnecting",
        40 => "connecting",
        50 => "local",
        60 => "site",
        70 => "connected",
        _ => "unknown",
    }
}

fn kind_name(t: &str) -> &'static str {
    match t {
        "802-11-wireless" => "wifi",
        "802-3-ethernet" => "ethernet",
        "vpn" | "wireguard" => "vpn",
        "bluetooth" => "bluetooth",
        _ => "other",
    }
}

/// The document while NetworkManager is not on the bus, or not answering.
fn unavailable() -> Value {
    json!({"state": "unavailable", "wifi_enabled": false})
}

async fn read(conn: &Connection) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return unavailable();
    }
    let Some(nm) = util::get_all(conn, DEST, NM_PATH, DEST).await else {
        return unavailable();
    };
    let wifi = util::prop::<bool>(&nm, "WirelessEnabled").unwrap_or(false);
    let mut doc = json!({
        "state": state_name(util::prop::<u32>(&nm, "State").unwrap_or(0)),
        "wifi_enabled": wifi,
    });
    if let Some(primary) = primary(conn, &nm).await {
        doc["primary"] = primary;
    }
    // Absent when mobile broadband's switch cannot be read: airplane is then unknown, not off.
    if let Some(wwan) = util::prop::<bool>(&nm, "WwanEnabled") {
        doc["airplane"] = json!(!wifi && !wwan);
    }
    doc
}

async fn primary(conn: &Connection, nm: &util::Props) -> Option<Value> {
    let path = util::prop::<OwnedObjectPath>(nm, "PrimaryConnection")?;
    if path.as_str() == "/" {
        return None;
    }
    let act = util::get_all(conn, DEST, path.as_str(), ACTIVE_IF).await?;
    let kind = kind_name(&util::prop::<String>(&act, "Type").unwrap_or_default());
    let mut out =
        json!({"kind": kind, "name": util::prop::<String>(&act, "Id").unwrap_or_default()});
    if kind == "wifi"
        && let Some(s) = wifi_strength(conn, &act).await
    {
        out["strength"] = s.into();
    }
    Some(out)
}

async fn wifi_strength(conn: &Connection, act: &util::Props) -> Option<u8> {
    let devices = util::prop::<Vec<OwnedObjectPath>>(act, "Devices")?;
    let dev = devices.first()?;
    let w = util::get_all(conn, DEST, dev.as_str(), WIRELESS_IF).await?;
    let ap = util::prop::<OwnedObjectPath>(&w, "ActiveAccessPoint")?;
    if ap.as_str() == "/" {
        return None;
    }
    let a = util::get_all(conn, DEST, ap.as_str(), AP_IF).await?;
    util::prop::<u8>(&a, "Strength")
}

/// The wifi devices NetworkManager knows, in its order. `None` when NetworkManager does not answer.
async fn wifi_devices(conn: &Connection) -> Option<Vec<OwnedObjectPath>> {
    let nm = util::get_all(conn, DEST, NM_PATH, DEST).await?;
    let devices = util::prop::<Vec<OwnedObjectPath>>(&nm, "Devices").unwrap_or_default();
    let mut wifi = Vec::new();
    for dev in devices {
        let Some(props) = util::get_all(conn, DEST, dev.as_str(), DEVICE_IF).await else {
            continue;
        };
        if util::prop::<u32>(&props, "DeviceType") == Some(DEVICE_TYPE_WIFI) {
            wifi.push(dev);
        }
    }
    Some(wifi)
}

/// One access point as the scan sees it.
struct Ap {
    ssid: Vec<u8>,
    strength: u8,
    secure: bool,
}

/// The access points a wifi device lists (`AccessPoints`), hidden ones (empty SSID) left out.
async fn access_points(conn: &Connection, dev: &OwnedObjectPath) -> Vec<Ap> {
    let Some(w) = util::get_all(conn, DEST, dev.as_str(), WIRELESS_IF).await else {
        return Vec::new();
    };
    let paths = util::prop::<Vec<OwnedObjectPath>>(&w, "AccessPoints").unwrap_or_default();
    let mut out = Vec::new();
    for path in paths {
        if let Some(ap) = access_point(conn, path.as_str()).await
            && !ap.ssid.is_empty()
        {
            out.push(ap);
        }
    }
    out
}

async fn access_point(conn: &Connection, path: &str) -> Option<Ap> {
    let a = util::get_all(conn, DEST, path, AP_IF).await?;
    let flag = |key: &str| util::prop::<u32>(&a, key).unwrap_or(0);
    let secure =
        flag("Flags") & AP_FLAGS_PRIVACY != 0 || flag("WpaFlags") != 0 || flag("RsnFlags") != 0;
    Some(Ap {
        ssid: util::prop::<Vec<u8>>(&a, "Ssid")?,
        strength: util::prop::<u8>(&a, "Strength").unwrap_or(0),
        secure,
    })
}

/// Saved wifi profiles with their SSID bytes. Settings the bus refuses or cannot read leave their
/// profile out: a network is "known" only when a profile for it was seen.
async fn wifi_profiles(conn: &Connection) -> Vec<(OwnedObjectPath, Vec<u8>)> {
    let Ok(reply) = util::call(
        conn,
        DEST,
        SETTINGS_PATH,
        SETTINGS_IF,
        "ListConnections",
        &(),
    )
    .await
    else {
        return Vec::new();
    };
    let Ok(paths) = reply.body().deserialize::<Vec<OwnedObjectPath>>() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for path in paths {
        let Ok(reply) = util::call(conn, DEST, path.as_str(), SETTING_IF, "GetSettings", &()).await
        else {
            continue;
        };
        let Ok(settings) = reply
            .body()
            .deserialize::<HashMap<String, HashMap<String, OwnedValue>>>()
        else {
            continue;
        };
        let ssid = settings
            .get("802-11-wireless")
            .and_then(|w| w.get("ssid"))
            .and_then(|v| v.try_clone().ok())
            .and_then(|v| Vec::<u8>::try_from(v).ok());
        if let Some(ssid) = ssid {
            out.push((path, ssid));
        }
    }
    out
}

/// One rescan request to every wifi device. NetworkManager answers at once and reports the new list
/// through the device's own PropertiesChanged; a refusal leaves the list as it was.
async fn request_scans(conn: &Connection) {
    let Some(devices) = wifi_devices(conn).await else {
        return;
    };
    for dev in devices {
        let options: HashMap<&str, zbus::zvariant::Value<'_>> = HashMap::new();
        if let Err(e) = util::call(
            conn,
            DEST,
            dev.as_str(),
            WIRELESS_IF,
            "RequestScan",
            &(options,),
        )
        .await
        {
            tracing::debug!(error = %e, "wifi rescan refused");
        }
    }
}

const WIFI_OFF: &str = "error.network.wifi_off";
const NO_WIFI_DEVICE: &str = "error.network.no_wifi_device";
const UNAVAILABLE_KEY: &str = "error.network.unavailable";

/// `svc.network.scan`: `{available, networks?, reason?}`. `networks` lists each SSID once (its
/// strongest access point), the active one first, then by strength. `reason` (i18n key) says why
/// nothing can be listed; it is absent while `available`.
async fn scan_doc(conn: &Connection) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return scan_unavailable();
    }
    let Some(nm) = util::get_all(conn, DEST, NM_PATH, DEST).await else {
        return scan_unavailable();
    };
    match util::prop::<bool>(&nm, "WirelessEnabled") {
        Some(true) => {}
        Some(false) => return scan_reason(WIFI_OFF),
        None => return scan_unavailable(),
    }
    let Some(devices) = wifi_devices(conn).await else {
        return scan_unavailable();
    };
    if devices.is_empty() {
        return scan_reason(NO_WIFI_DEVICE);
    }
    let profiles = wifi_profiles(conn).await;
    let mut best: BTreeMap<Vec<u8>, Ap> = BTreeMap::new();
    let mut active: Option<Vec<u8>> = None;
    for dev in &devices {
        if active.is_none() {
            active = active_ssid(conn, dev).await;
        }
        for ap in access_points(conn, dev).await {
            if best.get(&ap.ssid).is_none_or(|b| b.strength < ap.strength) {
                best.insert(ap.ssid.clone(), ap);
            }
        }
    }
    let mut rows: Vec<(bool, u8, String, Value)> = best
        .into_iter()
        .map(|(ssid, ap)| {
            let is_active = active.as_ref() == Some(&ssid);
            let known = profiles.iter().any(|(_, s)| *s == ssid);
            let name = String::from_utf8_lossy(&ssid).into_owned();
            let row = json!({
                "ssid": name,
                "strength": ap.strength,
                "secure": ap.secure,
                "known": known,
                "active": is_active,
            });
            (is_active, ap.strength, name, row)
        })
        .collect();
    rows.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
    let networks: Vec<Value> = rows.into_iter().map(|r| r.3).collect();
    json!({"available": true, "networks": networks})
}

/// The SSID of a wifi device's active access point, if it has one.
async fn active_ssid(conn: &Connection, dev: &OwnedObjectPath) -> Option<Vec<u8>> {
    let w = util::get_all(conn, DEST, dev.as_str(), WIRELESS_IF).await?;
    let ap = util::prop::<OwnedObjectPath>(&w, "ActiveAccessPoint")?;
    if ap.as_str() == "/" {
        return None;
    }
    access_point(conn, ap.as_str()).await.map(|a| a.ssid)
}

fn scan_reason(key: &str) -> Value {
    json!({"available": false, "reason": key})
}

/// The scan document while NetworkManager is gone.
fn scan_unavailable() -> Value {
    scan_reason(UNAVAILABLE_KEY)
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    #[test]
    fn only_permission_errors_are_refusals() {
        let fdo = |e: zbus::fdo::Error| zbus::Error::FDO(Box::new(e));
        assert_eq!(
            WifiError::of(&fdo(zbus::fdo::Error::AccessDenied("no".into()))),
            WifiError::Refused
        );
        assert_eq!(
            WifiError::of(&fdo(zbus::fdo::Error::ServiceUnknown("gone".into()))),
            WifiError::Unavailable
        );
        assert_eq!(
            WifiError::of(&zbus::Error::Failure("broken".into())),
            WifiError::Unavailable
        );
    }

    #[derive(Default)]
    struct Docs(Mutex<Vec<Value>>);

    impl DocSink for Docs {
        fn set(&self, doc: Value) {
            self.0.lock().unwrap().push(doc);
        }
    }

    /// Scans are requested at once and then once per `every`, on the paused clock, and nothing is
    /// requested after the loop's task ends (the last unsubscribe).
    #[tokio::test(start_paused = true)]
    async fn scans_run_at_once_then_every_interval_until_the_task_ends() {
        let docs = Arc::new(Docs::default());
        let em = Emitter::new(docs.clone());
        let requests = Arc::new(AtomicUsize::new(0));
        let counted = requests.clone();
        let task = tokio::spawn(async move {
            scan_loop(
                &em,
                futures_util::stream::pending::<zbus::Result<()>>(),
                Duration::from_secs(15),
                |_: &()| false,
                move || {
                    counted.fetch_add(1, Ordering::SeqCst);
                    async {}
                },
                || async { json!({"available": true, "networks": []}) },
                scan_unavailable(),
            )
            .await;
        });
        tokio::time::sleep(Duration::from_secs(1)).await;
        assert_eq!(requests.load(Ordering::SeqCst), 1, "a scan at once");
        // Ticks at 15, 30 and 45 s; the sleep ends at 45.5 s, after all three.
        tokio::time::sleep(Duration::from_millis(44_500)).await;
        assert_eq!(requests.load(Ordering::SeqCst), 4, "0, 15, 30 and 45 s");

        task.abort();
        tokio::time::sleep(Duration::from_secs(120)).await;
        assert_eq!(
            requests.load(Ordering::SeqCst),
            4,
            "no scans once unsubscribed"
        );
    }

    /// The bus going away ends the loop and says so: the last document is `unavailable`, not the
    /// networks it last listed (rule 2).
    #[tokio::test(start_paused = true)]
    async fn a_lost_bus_ends_the_loop_with_an_unavailable_document() {
        let docs = Arc::new(Docs::default());
        let em = Emitter::new(docs.clone());
        let events = futures_util::stream::iter(vec![Err::<bool, zbus::Error>(
            zbus::Error::Failure("socket closed".into()),
        )]);
        scan_loop(
            &em,
            events,
            Duration::from_secs(3600),
            |wanted: &bool| *wanted,
            || async {},
            || async { json!({"available": true, "networks": []}) },
            scan_unavailable(),
        )
        .await;
        let last = docs.0.lock().unwrap().last().cloned();
        assert_eq!(
            last,
            Some(json!({"available": false, "reason": UNAVAILABLE_KEY}))
        );
    }
}
