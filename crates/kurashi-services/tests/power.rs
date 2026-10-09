mod common;

use std::time::Duration;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::power;

struct Root {
    on_battery: bool,
}
#[zbus::interface(name = "org.freedesktop.UPower")]
impl Root {
    #[zbus(property)]
    fn on_battery(&self) -> bool {
        self.on_battery
    }
}

struct Dev {
    present: bool,
    pct: f64,
    state: u32,
}
#[zbus::interface(name = "org.freedesktop.UPower.Device")]
impl Dev {
    #[zbus(property)]
    fn is_present(&self) -> bool {
        self.present
    }
    #[zbus(property)]
    fn percentage(&self) -> f64 {
        self.pct
    }
    #[zbus(property)]
    fn state(&self) -> u32 {
        self.state
    }
    #[zbus(property)]
    fn time_to_empty(&self) -> i64 {
        7200
    }
    #[zbus(property)]
    fn time_to_full(&self) -> i64 {
        0
    }
}

const DISPLAY: &str = "/org/freedesktop/UPower/devices/DisplayDevice";

#[tokio::test]
async fn power_lifecycle() {
    let bus = TestBus::start();
    let rec = Rec::new();
    // UPower not on the bus yet.
    let (handle, _c) = power::start(bus.conn().await, rec.clone()).await.unwrap();
    let d = rec.wait("absent", |_| true).await;
    assert_eq!(
        d,
        serde_json::json!({"present": false, "on_battery": false})
    );

    let srv = bus.server("org.freedesktop.UPower").await;
    srv.object_server()
        .at("/org/freedesktop/UPower", Root { on_battery: true })
        .await
        .unwrap();
    srv.object_server()
        .at(
            DISPLAY,
            Dev {
                present: true,
                pct: 80.0,
                state: 2,
            },
        )
        .await
        .unwrap();
    // NameOwnerChanged fired on request_name, before objects were served; the property signal
    // below (or the next event) re-reads. Trigger one explicitly.
    let r = srv
        .object_server()
        .interface::<_, Dev>(DISPLAY)
        .await
        .unwrap();
    r.get()
        .await
        .percentage_changed(r.signal_emitter())
        .await
        .unwrap();

    let d = rec.wait("battery", |d| d["present"] == true).await;
    assert_eq!(d["percent"], 80.0);
    assert_eq!(d["state"], "discharging");
    assert_eq!(d["on_battery"], true);
    assert_eq!(d["time_to_empty_s"], 7200);
    assert!(d.get("time_to_full_s").is_none());
    assert_no_null(&d);

    // Property change.
    r.get_mut().await.pct = 55.0;
    r.get_mut().await.state = 1;
    r.get()
        .await
        .percentage_changed(r.signal_emitter())
        .await
        .unwrap();
    let d = rec.wait("55", |d| d["percent"] == 55.0).await;
    assert_eq!(d["state"], "charging");

    // No battery present.
    r.get_mut().await.present = false;
    r.get()
        .await
        .is_present_changed(r.signal_emitter())
        .await
        .unwrap();
    rec.wait("not present", |d| d["present"] == false).await;

    // Owner disappears.
    r.get_mut().await.present = true;
    r.get()
        .await
        .is_present_changed(r.signal_emitter())
        .await
        .unwrap();
    rec.wait("back", |d| d["present"] == true).await;
    drop(r);
    drop(srv);
    rec.wait("owner gone", |d| d["present"] == false).await;

    drop(handle);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let n = rec.count();
    let srv = bus.server("org.freedesktop.UPower").await;
    srv.object_server()
        .at("/org/freedesktop/UPower", Root { on_battery: false })
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(rec.count(), n, "sink called after handle drop");
}
