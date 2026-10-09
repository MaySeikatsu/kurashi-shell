//! `svc.power` — UPower display device, and the power profile from power-profiles-daemon. No UPower
//! (or one that does not answer) → `available:false`; UPower answers and there is no battery →
//! `available:true, present:false`. `profile` and `profiles` appear while the profile daemon answers;
//! otherwise `profile_reason` (i18n key) says why there are none.

use std::sync::Arc;

use anyhow::Result;
use serde_json::{Value, json};
use zbus::Connection;

use crate::power_profiles::{self, ProfileError};
use crate::util::{self, DocSink, Emitter, ServiceHandle};

const DEST: &str = "org.freedesktop.UPower";
const ROOT_PATH: &str = "/org/freedesktop/UPower";
const DISPLAY: &str = "/org/freedesktop/UPower/devices/DisplayDevice";

/// `power.profile`: switches the profile on the connection the document reads through.
#[derive(Clone)]
pub struct Commands {
    conn: Connection,
}

impl Commands {
    pub async fn set_profile(&self, name: &str) -> Result<(), ProfileError> {
        power_profiles::set(&self.conn, name).await
    }
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    let events = util::watch(
        &conn,
        vec![
            util::props_changed(ROOT_PATH)?,
            util::name_owner_changed(DEST)?,
            util::props_changed(power_profiles::PATH)?,
            util::name_owner_changed(power_profiles::DEST)?,
        ],
    )
    .await?;
    let em = Emitter::new(sink);
    em.emit(read(&conn).await);
    let task = {
        let conn = conn.clone();
        tokio::spawn(async move {
            util::follow("power", &em, events, unavailable(), |_| read(&conn)).await;
        })
    };
    Ok((ServiceHandle::new(task), Commands { conn }))
}

fn state_name(s: u32) -> &'static str {
    match s {
        1 => "charging",
        2 => "discharging",
        3 => "empty",
        4 => "full",
        5 => "pending_charge",
        6 => "pending_discharge",
        _ => "unknown",
    }
}

/// The battery part while UPower is not on the bus, does not answer, or is silent: `present` and
/// `on_battery` are fillers then, `available:false` says nothing is known about them.
fn battery_unavailable() -> Value {
    json!({"available": false, "present": false, "on_battery": false})
}

/// The whole document once its signal streams have ended: the profile is unknown too.
fn unavailable() -> Value {
    let mut doc = battery_unavailable();
    doc["profile_reason"] = json!(power_profiles::UNAVAILABLE);
    doc
}

async fn read(conn: &Connection) -> Value {
    let mut doc = battery(conn).await;
    let fields = doc.as_object_mut().expect("the battery part is an object");
    match power_profiles::read(conn).await {
        Ok(p) => {
            fields.insert("profile".into(), json!(p.active));
            fields.insert("profiles".into(), json!(p.names));
        }
        Err(key) => {
            fields.insert("profile_reason".into(), json!(key));
        }
    }
    doc
}

async fn battery(conn: &Connection) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return battery_unavailable();
    }
    // Both objects must answer: a silent UPower says nothing about whether there is a battery.
    let root = util::get_all(conn, DEST, ROOT_PATH, DEST).await;
    let display = util::get_all(conn, DEST, DISPLAY, "org.freedesktop.UPower.Device").await;
    let (Some(root), Some(p)) = (root, display) else {
        return battery_unavailable();
    };
    let on_battery = util::prop::<bool>(&root, "OnBattery").unwrap_or(false);
    if !util::prop::<bool>(&p, "IsPresent").unwrap_or(false) {
        return json!({"available": true, "present": false, "on_battery": on_battery});
    }
    let mut doc = json!({
        "available": true,
        "present": true,
        "percent": util::prop::<f64>(&p, "Percentage").unwrap_or(0.0),
        "state": state_name(util::prop::<u32>(&p, "State").unwrap_or(0)),
        "on_battery": on_battery,
    });
    let d = doc.as_object_mut().unwrap();
    // 0 means "unknown" in UPower; absence is how documents say that.
    for (key, prop) in [
        ("time_to_empty_s", "TimeToEmpty"),
        ("time_to_full_s", "TimeToFull"),
    ] {
        if let Some(t) = util::prop::<i64>(&p, prop).filter(|t| *t > 0) {
            d.insert(key.into(), t.into());
        }
    }
    doc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lost_stream_leaves_no_profile_and_no_battery_claim() {
        let d = unavailable();
        assert_eq!(d["available"], false);
        assert_eq!(d["profile_reason"], power_profiles::UNAVAILABLE);
        assert!(d.get("profile").is_none() && d.get("profiles").is_none());
    }
}
