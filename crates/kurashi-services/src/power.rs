//! `svc.power` — UPower display device. No battery (or no UPower) → `present:false`.

use std::sync::Arc;

use anyhow::Result;
use serde_json::{Value, json};
use zbus::Connection;

use crate::util::{self, DocSink, Emitter, ServiceHandle};

const DEST: &str = "org.freedesktop.UPower";
const ROOT_PATH: &str = "/org/freedesktop/UPower";
const DISPLAY: &str = "/org/freedesktop/UPower/devices/DisplayDevice";

/// No commands yet; kept so every service has the same `start` signature.
pub struct Commands;

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    let events = util::watch(
        &conn,
        vec![
            util::props_changed(ROOT_PATH)?,
            util::name_owner_changed(DEST)?,
        ],
    )
    .await?;
    let em = Emitter::new(sink);
    em.emit(read(&conn).await);
    let task = tokio::spawn(async move {
        util::follow("power", &em, events, unavailable(), |_| read(&conn)).await;
    });
    Ok((ServiceHandle::new(task), Commands))
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

/// The document while UPower is not on the bus, or not answering.
fn unavailable() -> Value {
    json!({"present": false, "on_battery": false})
}

async fn read(conn: &Connection) -> Value {
    if !util::name_has_owner(conn, DEST).await {
        return unavailable();
    }
    let on_battery = match util::get_all(conn, DEST, ROOT_PATH, DEST).await {
        Some(p) => util::prop::<bool>(&p, "OnBattery").unwrap_or(false),
        None => false,
    };
    let Some(p) = util::get_all(conn, DEST, DISPLAY, "org.freedesktop.UPower.Device").await else {
        return json!({"present": false, "on_battery": on_battery});
    };
    if !util::prop::<bool>(&p, "IsPresent").unwrap_or(false) {
        return json!({"present": false, "on_battery": on_battery});
    }
    let mut doc = json!({
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
