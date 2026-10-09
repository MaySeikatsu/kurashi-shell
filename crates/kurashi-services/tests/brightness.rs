mod common;

use std::path::PathBuf;

use common::{Rec, TestBus, assert_no_null};
use kurashi_services::brightness;

/// Fake logind: SetBrightness writes the sysfs file, like the real one does.
struct Sess {
    dir: PathBuf,
}
#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl Sess {
    fn set_brightness(&self, subsystem: String, name: String, value: u32) {
        assert_eq!(subsystem, "backlight");
        std::fs::write(self.dir.join(name).join("brightness"), value.to_string()).unwrap();
    }
}

#[tokio::test]
async fn brightness_read_on_demand() {
    let bus = TestBus::start();
    let tmp = tempfile::tempdir().unwrap();

    // No backlight at all.
    let rec = Rec::new();
    let (_h, _c) = brightness::start_at(bus.conn().await, rec.clone(), tmp.path().to_owned())
        .await
        .unwrap();
    assert_eq!(rec.last().unwrap(), serde_json::json!({"present": false}));

    let dev = tmp.path().join("intel_backlight");
    std::fs::create_dir(&dev).unwrap();
    std::fs::write(dev.join("max_brightness"), "200\n").unwrap();
    std::fs::write(dev.join("brightness"), "50\n").unwrap();

    let srv = bus.server("org.freedesktop.login1").await;
    srv.object_server()
        .at(
            "/org/freedesktop/login1/session/auto",
            Sess {
                dir: tmp.path().to_owned(),
            },
        )
        .await
        .unwrap();

    let rec = Rec::new();
    let (handle, cmds) = brightness::start_at(bus.conn().await, rec.clone(), tmp.path().to_owned())
        .await
        .unwrap();
    let d = rec.last().unwrap();
    assert_eq!(d["percent"], 25.0);
    assert_eq!(d["max"], 200);
    assert_eq!(d["device"], "intel_backlight");
    assert_no_null(&d);

    // Our own change is reflected immediately.
    cmds.set_percent(100.0).await.unwrap();
    assert_eq!(rec.last().unwrap()["value"], 200);

    // External change is picked up only on refresh (documented deviation: no polling).
    std::fs::write(dev.join("brightness"), "100").unwrap();
    assert_eq!(rec.last().unwrap()["value"], 200);
    cmds.refresh();
    assert_eq!(rec.last().unwrap()["percent"], 50.0);

    let n = rec.count();
    drop(handle);
    std::fs::write(dev.join("brightness"), "10").unwrap();
    assert_eq!(rec.count(), n);
}
