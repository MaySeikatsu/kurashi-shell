//! `svc.bluetooth` — BlueZ adapter state and known devices (docs/tasks/M4-bluetooth.md).
//!
//! BlueZ publishes its tree through ObjectManager. The tree is read once and then kept in memory
//! by applying InterfacesAdded/Removed and PropertiesChanged: re-reading everything per signal
//! would cost a round trip for every RSSI tick while a scan runs. Only the scan this service
//! starts is owned here; BlueZ would otherwise keep it going for as long as our connection lives.

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Weak};

use anyhow::{Result, anyhow};
use futures_util::StreamExt;
use serde_json::{Map, Value, json};
use zbus::message::{Message, Type as MsgType};
use zbus::zvariant::{OwnedObjectPath, Value as ZValue};
use zbus::{Connection, MatchRule};

use crate::util::{self, DocSink, Emitter, Props, ServiceHandle};

const DEST: &str = "org.bluez";
const ROOT: &str = "/";
const TREE_PREFIX: &str = "/org/bluez/";
const OM_IF: &str = "org.freedesktop.DBus.ObjectManager";
const ADAPTER_IF: &str = "org.bluez.Adapter1";
const DEVICE_IF: &str = "org.bluez.Device1";
const BATTERY_IF: &str = "org.bluez.Battery1";

/// object path -> interface -> properties. Sorted, so "the first adapter" is stable across reads.
type Objects = BTreeMap<String, BTreeMap<String, Props>>;

/// Discovery we started. The service task owns it: aborting the task (dropping the handle) drops
/// this, and `Drop` stops the scan. `Commands` only holds a `Weak`, so a command issued after the
/// handle is gone cannot start a scan that nothing would ever stop.
struct Session {
    conn: Connection,
    /// Adapter path while our scan runs.
    scanning: tokio::sync::Mutex<Option<String>>,
}

impl Drop for Session {
    fn drop(&mut self) {
        let Some(adapter) = self.scanning.get_mut().take() else {
            return;
        };
        // Drop cannot await, so the stop goes out on a detached task. Outside a runtime there is
        // nothing to do: BlueZ ends a client's scan when that client's bus connection closes.
        if let Ok(rt) = tokio::runtime::Handle::try_current() {
            let conn = self.conn.clone();
            rt.spawn(async move {
                let _ = stop_scan(&conn, &adapter).await;
            });
        }
    }
}

#[derive(Clone)]
pub struct Commands {
    conn: Connection,
    session: Weak<Session>,
}

impl Commands {
    pub async fn set_powered(&self, on: bool) -> Result<()> {
        let adapter = adapter_path(&self.conn).await?;
        let p = zbus::fdo::PropertiesProxy::builder(&self.conn)
            .destination(DEST)?
            .path(adapter.as_str())?
            .build()
            .await?;
        p.set(ADAPTER_IF.try_into()?, "Powered", ZValue::from(on))
            .await?;
        Ok(())
    }

    pub async fn connect(&self, address: &str) -> Result<()> {
        device_call(&self.conn, address, "Connect").await
    }

    pub async fn disconnect(&self, address: &str) -> Result<()> {
        device_call(&self.conn, address, "Disconnect").await
    }

    /// Starts a scan owned by this service; it stops when the handle drops.
    pub async fn start_discovery(&self) -> Result<()> {
        let session = self
            .session
            .upgrade()
            .ok_or_else(|| anyhow!("bluetooth service is not running"))?;
        // Held across the call so two commands cannot both start a scan.
        let mut scanning = session.scanning.lock().await;
        if scanning.is_some() {
            return Ok(());
        }
        let adapter = adapter_path(&self.conn).await?;
        util::call(
            &self.conn,
            DEST,
            &adapter,
            ADAPTER_IF,
            "StartDiscovery",
            &(),
        )
        .await?;
        *scanning = Some(adapter);
        Ok(())
    }

    /// Only stops a scan this service started; BlueZ rejects a stop from a client that started none.
    pub async fn stop_discovery(&self) -> Result<()> {
        // Handle gone: its drop already stopped the scan.
        let Some(session) = self.session.upgrade() else {
            return Ok(());
        };
        let adapter = session.scanning.lock().await.take();
        match adapter {
            Some(adapter) => stop_scan(&self.conn, &adapter).await,
            None => Ok(()),
        }
    }
}

async fn device_call(conn: &Connection, address: &str, method: &str) -> Result<()> {
    let device = device_path(conn, address).await?;
    util::call(conn, DEST, &device, DEVICE_IF, method, &()).await?;
    Ok(())
}

async fn stop_scan(conn: &Connection, adapter: &str) -> Result<()> {
    util::call(conn, DEST, adapter, ADAPTER_IF, "StopDiscovery", &()).await?;
    Ok(())
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    // Rules first, then the snapshot, so no change can slip between the two (see util::watch).
    let mut events = util::watch(
        &conn,
        vec![
            om_rule("InterfacesAdded")?,
            om_rule("InterfacesRemoved")?,
            props_rule()?,
            util::name_owner_changed(DEST)?,
        ],
    )
    .await?;
    let session = Arc::new(Session {
        conn: conn.clone(),
        scanning: tokio::sync::Mutex::new(None),
    });
    let commands = Commands {
        conn: conn.clone(),
        session: Arc::downgrade(&session),
    };
    let em = Emitter::new(sink);
    // A failed snapshot is not fatal: the signals that follow rebuild the tree.
    let mut objects = snapshot(&conn).await.unwrap_or_default();
    em.emit(render(&objects));
    let task = tokio::spawn(async move {
        while let Some(msg) = events.next().await {
            let Ok(msg) = msg else {
                continue;
            };
            apply(&conn, &session, &mut objects, &msg).await;
            em.emit(render(&objects));
        }
        util::ended("bluetooth", &em, json!({"available": false}));
    });
    Ok((ServiceHandle::new(task), commands))
}

/// Applies one bus message to the cache. Signals outside BlueZ's tree are ignored.
async fn apply(conn: &Connection, session: &Session, objects: &mut Objects, msg: &Message) {
    let header = msg.header();
    let (Some(iface), Some(member)) = (header.interface(), header.member()) else {
        return;
    };
    let body = msg.body();
    match (iface.as_str(), member.as_str()) {
        (OM_IF, "InterfacesAdded") => {
            let Ok((path, added)) = body.deserialize::<(OwnedObjectPath, HashMap<String, Props>)>()
            else {
                return;
            };
            if !path.as_str().starts_with(TREE_PREFIX) {
                return;
            }
            objects.entry(path.to_string()).or_default().extend(added);
        }
        (OM_IF, "InterfacesRemoved") => {
            let Ok((path, gone)) = body.deserialize::<(OwnedObjectPath, Vec<String>)>() else {
                return;
            };
            if let Some(ifaces) = objects.get_mut(path.as_str()) {
                for name in gone {
                    ifaces.remove(&name);
                }
                if ifaces.is_empty() {
                    objects.remove(path.as_str());
                }
            }
        }
        ("org.freedesktop.DBus.Properties", "PropertiesChanged") => {
            let Some(path) = header.path().map(ToString::to_string) else {
                return;
            };
            let Ok((name, changed, invalidated)) =
                body.deserialize::<(String, Props, Vec<String>)>()
            else {
                return;
            };
            // An interface we were never told about is ignored: its InterfacesAdded carries the
            // full property set when it appears.
            let Some(props) = objects.get_mut(&path).and_then(|i| i.get_mut(&name)) else {
                return;
            };
            props.extend(changed);
            if !invalidated.is_empty() {
                // BlueZ does not send these values with the signal, so re-read the interface.
                if let Some(fresh) = util::get_all(conn, DEST, &path, &name).await {
                    *props = fresh;
                }
            }
        }
        ("org.freedesktop.DBus", "NameOwnerChanged") => {
            let Ok((_, _, new_owner)) = body.deserialize::<(String, String, String)>() else {
                return;
            };
            if new_owner.is_empty() {
                // BlueZ is gone: its objects and any scan it was running went with it.
                objects.clear();
                *session.scanning.lock().await = None;
            } else {
                *objects = snapshot(conn).await.unwrap_or_default();
            }
        }
        _ => {}
    }
}

/// GetManagedObjects, but only once org.bluez has an owner. Calling a name nobody owns would make
/// the bus start bluetoothd just because the shell asked about Bluetooth.
async fn snapshot(conn: &Connection) -> Option<Objects> {
    if !util::name_has_owner(conn, DEST).await {
        return None;
    }
    let om = zbus::fdo::ObjectManagerProxy::builder(conn)
        .destination(DEST)
        .ok()?
        .path(ROOT)
        .ok()?
        .build()
        .await
        .ok()?;
    let managed = om.get_managed_objects().await.ok()?;
    Some(
        managed
            .into_iter()
            .map(|(path, ifaces)| {
                let ifaces: BTreeMap<String, Props> = ifaces
                    .into_iter()
                    .map(|(name, props)| (name.to_string(), props))
                    .collect();
                (path.to_string(), ifaces)
            })
            .collect(),
    )
}

/// Current adapter (as `render` picks it) for a command, or an error saying why there is none.
async fn adapter_path(conn: &Connection) -> Result<String> {
    let objects = snapshot(conn)
        .await
        .ok_or_else(|| anyhow!("bluetooth is not running"))?;
    first_adapter(&objects)
        .map(str::to_owned)
        .ok_or_else(|| anyhow!("no bluetooth adapter"))
}

async fn device_path(conn: &Connection, address: &str) -> Result<String> {
    let objects = snapshot(conn)
        .await
        .ok_or_else(|| anyhow!("bluetooth is not running"))?;
    objects
        .iter()
        .find(|(_, ifaces)| {
            ifaces
                .get(DEVICE_IF)
                .and_then(|d| util::prop::<String>(d, "Address"))
                .is_some_and(|a| a.eq_ignore_ascii_case(address))
        })
        .map(|(path, _)| path.clone())
        .ok_or_else(|| anyhow!("unknown bluetooth device {address}"))
}

/// The lowest adapter path. Every reader goes through here so "the adapter" never disagrees.
fn first_adapter(objects: &Objects) -> Option<&str> {
    objects
        .iter()
        .find(|(_, ifaces)| ifaces.contains_key(ADAPTER_IF))
        .map(|(path, _)| path.as_str())
}

/// `{available:false}` without an adapter; otherwise adapter state plus its devices, connected
/// first, then paired, then by name. Absent optional fields are omitted, never null.
fn render(objects: &Objects) -> Value {
    let Some(adapter_path) = first_adapter(objects) else {
        return json!({"available": false});
    };
    let adapter = &objects[adapter_path][ADAPTER_IF];
    let mut devices: Vec<Device> = objects
        .values()
        .filter_map(|ifaces| Device::read(ifaces, adapter_path))
        .collect();
    devices.sort_by(|a, b| {
        (!a.connected, !a.paired)
            .cmp(&(!b.connected, !b.paired))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
            .then_with(|| a.address.cmp(&b.address))
    });
    json!({
        "available": true,
        "powered": util::prop::<bool>(adapter, "Powered").unwrap_or(false),
        "discovering": util::prop::<bool>(adapter, "Discovering").unwrap_or(false),
        "devices": devices.iter().map(Device::to_json).collect::<Vec<_>>(),
    })
}

struct Device {
    address: String,
    name: String,
    icon: Option<String>,
    paired: bool,
    connected: bool,
    battery: Option<u8>,
}

impl Device {
    /// `None` for anything that is not a device of `adapter` (GATT services, other adapters).
    fn read(ifaces: &BTreeMap<String, Props>, adapter: &str) -> Option<Self> {
        let dev = ifaces.get(DEVICE_IF)?;
        if util::prop::<OwnedObjectPath>(dev, "Adapter")?.as_str() != adapter {
            return None;
        }
        let address = util::prop::<String>(dev, "Address")?;
        // BlueZ always sets Alias (falling back to the remote name, then the address); Name can be
        // absent. Alias is what Bluetooth UIs show, so it wins.
        let name = non_empty(util::prop::<String>(dev, "Alias"))
            .or_else(|| non_empty(util::prop::<String>(dev, "Name")))
            .unwrap_or_else(|| address.clone());
        Some(Self {
            icon: non_empty(util::prop::<String>(dev, "Icon")),
            paired: util::prop::<bool>(dev, "Paired").unwrap_or(false),
            connected: util::prop::<bool>(dev, "Connected").unwrap_or(false),
            battery: ifaces
                .get(BATTERY_IF)
                .and_then(|b| util::prop::<u8>(b, "Percentage")),
            name,
            address,
        })
    }

    fn to_json(&self) -> Value {
        let mut out = Map::new();
        out.insert("address".into(), self.address.clone().into());
        out.insert("name".into(), self.name.clone().into());
        out.insert("paired".into(), self.paired.into());
        out.insert("connected".into(), self.connected.into());
        if let Some(icon) = &self.icon {
            out.insert("icon".into(), icon.clone().into());
        }
        if let Some(battery) = self.battery {
            out.insert("battery".into(), battery.into());
        }
        Value::Object(out)
    }
}

fn non_empty(s: Option<String>) -> Option<String> {
    s.filter(|s| !s.is_empty())
}

fn om_rule(member: &'static str) -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .sender(DEST)?
        .interface(OM_IF)?
        .member(member)?
        .path(ROOT)?
        .build())
}

fn props_rule() -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .sender(DEST)?
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path_namespace("/org/bluez")?
        .build())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::{ObjectPath, OwnedValue, Str};

    const ADAPTER: &str = "/org/bluez/hci0";

    fn props(pairs: Vec<(&str, OwnedValue)>) -> Props {
        pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
    }

    fn text(v: &str) -> OwnedValue {
        OwnedValue::from(Str::from(v))
    }

    fn path_value(v: &str) -> OwnedValue {
        OwnedValue::from(ObjectPath::try_from(v).unwrap())
    }

    fn adapter_objects() -> Objects {
        let adapter = props(vec![
            ("Powered", OwnedValue::from(true)),
            ("Discovering", OwnedValue::from(false)),
        ]);
        Objects::from([(
            ADAPTER.to_owned(),
            BTreeMap::from([(ADAPTER_IF.to_owned(), adapter)]),
        )])
    }

    fn add_device(objects: &mut Objects, id: &str, alias: &str, paired: bool, connected: bool) {
        let dev = props(vec![
            ("Adapter", path_value(ADAPTER)),
            ("Address", text(&format!("00:00:00:00:00:{id}"))),
            ("Alias", text(alias)),
            ("Paired", OwnedValue::from(paired)),
            ("Connected", OwnedValue::from(connected)),
        ]);
        objects.insert(
            format!("{ADAPTER}/dev_{id}"),
            BTreeMap::from([(DEVICE_IF.to_owned(), dev)]),
        );
    }

    #[test]
    fn no_adapter_is_unavailable() {
        assert_eq!(render(&Objects::new()), json!({"available": false}));
    }

    #[test]
    fn devices_sort_connected_then_paired_then_name() {
        let mut o = adapter_objects();
        add_device(&mut o, "01", "Zeta", true, false);
        add_device(&mut o, "02", "alpha", false, false);
        add_device(&mut o, "03", "Mid", true, true);
        add_device(&mut o, "04", "Beta", true, false);
        let doc = render(&o);
        let names: Vec<&str> = doc["devices"]
            .as_array()
            .unwrap()
            .iter()
            .map(|d| d["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, ["Mid", "Beta", "Zeta", "alpha"]);
    }

    #[test]
    fn name_falls_back_and_optional_fields_are_omitted() {
        let mut o = adapter_objects();
        // Empty alias: the remote Name stands in, and the icon is kept.
        let named = props(vec![
            ("Adapter", path_value(ADAPTER)),
            ("Address", text("00:00:00:00:00:01")),
            ("Alias", text("")),
            ("Name", text("Remote")),
            ("Icon", text("audio-headset")),
            ("Paired", OwnedValue::from(false)),
            ("Connected", OwnedValue::from(false)),
        ]);
        o.insert(
            format!("{ADAPTER}/dev_01"),
            BTreeMap::from([(DEVICE_IF.to_owned(), named)]),
        );
        // Neither alias nor name: the address stands in, no icon. A battery shows up when present.
        let bare = props(vec![
            ("Adapter", path_value(ADAPTER)),
            ("Address", text("00:00:00:00:00:02")),
            ("Paired", OwnedValue::from(false)),
            ("Connected", OwnedValue::from(false)),
        ]);
        let mut ifaces = BTreeMap::from([(DEVICE_IF.to_owned(), bare)]);
        ifaces.insert(
            BATTERY_IF.to_owned(),
            props(vec![("Percentage", OwnedValue::from(80u8))]),
        );
        o.insert(format!("{ADAPTER}/dev_02"), ifaces);
        // A GATT service below a device is not a device.
        o.insert(
            format!("{ADAPTER}/dev_01/service0001"),
            BTreeMap::from([("org.bluez.GattService1".to_owned(), Props::new())]),
        );

        assert_eq!(
            render(&o)["devices"],
            json!([
                {"address": "00:00:00:00:00:02", "name": "00:00:00:00:00:02", "paired": false,
                 "connected": false, "battery": 80},
                {"address": "00:00:00:00:00:01", "name": "Remote", "icon": "audio-headset",
                 "paired": false, "connected": false},
            ])
        );
    }
}
