//! `svc.network` — NetworkManager state, primary connection, wifi strength.

use std::sync::Arc;

use anyhow::Result;
use serde_json::{Value, json};
use zbus::Connection;
use zbus::zvariant::OwnedObjectPath;

use crate::util::{self, DocSink, Emitter, ServiceHandle};

const DEST: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const ACTIVE_IF: &str = "org.freedesktop.NetworkManager.Connection.Active";

/// Why NetworkManager did not take a `WirelessEnabled` write. The caller maps each to an i18n key
/// (PROTOCOL §8, `network.wifi`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WifiError {
    /// NetworkManager's polkit check, or the bus policy, said no.
    Refused,
    /// No NetworkManager on the bus, or the call failed for another reason.
    Unavailable,
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
        self.write_wifi(on).await.map_err(|e| {
            tracing::warn!(error = %e, "NetworkManager did not take the wifi change");
            WifiError::of(&e)
        })
    }

    async fn write_wifi(&self, on: bool) -> zbus::Result<()> {
        let p = zbus::fdo::PropertiesProxy::builder(&self.conn)
            .destination(DEST)?
            .path(NM_PATH)?
            .build()
            .await?;
        p.set(
            DEST.try_into()?,
            "WirelessEnabled",
            zbus::zvariant::Value::from(on),
        )
        .await?;
        Ok(())
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
    let mut doc = json!({
        "state": state_name(util::prop::<u32>(&nm, "State").unwrap_or(0)),
        "wifi_enabled": util::prop::<bool>(&nm, "WirelessEnabled").unwrap_or(false),
    });
    if let Some(primary) = primary(conn, &nm).await {
        doc["primary"] = primary;
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
    if kind == "wifi" {
        if let Some(s) = wifi_strength(conn, &act).await {
            out["strength"] = s.into();
        }
    }
    Some(out)
}

async fn wifi_strength(conn: &Connection, act: &util::Props) -> Option<u8> {
    let devices = util::prop::<Vec<OwnedObjectPath>>(act, "Devices")?;
    let dev = devices.first()?;
    let w = util::get_all(
        conn,
        DEST,
        dev.as_str(),
        "org.freedesktop.NetworkManager.Device.Wireless",
    )
    .await?;
    let ap = util::prop::<OwnedObjectPath>(&w, "ActiveAccessPoint")?;
    if ap.as_str() == "/" {
        return None;
    }
    let a = util::get_all(
        conn,
        DEST,
        ap.as_str(),
        "org.freedesktop.NetworkManager.AccessPoint",
    )
    .await?;
    util::prop::<u8>(&a, "Strength")
}

#[cfg(test)]
mod tests {
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
}
