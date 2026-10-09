//! Private bus + recording sink. Nothing here ever touches the user's real session/system bus.
#![allow(dead_code)]

use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_notify::DocSink;
use serde_json::Value;
use zbus::Connection;

pub struct TestBus {
    child: Child,
    pub addr: String,
    _dir: tempfile::TempDir,
}

impl TestBus {
    pub fn start() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let conf = dir.path().join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type>
<listen>unix:tmpdir={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                dir.path().display()
            ),
        )
        .unwrap();
        let mut child = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut addr = String::new();
        BufReader::new(child.stdout.as_mut().unwrap())
            .read_line(&mut addr)
            .unwrap();
        Self {
            child,
            addr: addr.trim().to_owned(),
            _dir: dir,
        }
    }

    pub async fn conn(&self) -> Connection {
        zbus::connection::Builder::address(self.addr.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }

    /// A connection that also owns `name`, for serving fake objects.
    pub async fn server(&self, name: &str) -> Connection {
        let c = self.conn().await;
        c.request_name(name.to_owned()).await.unwrap();
        c
    }
}

impl Drop for TestBus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[derive(Default)]
pub struct Rec(Mutex<Vec<Value>>);

impl DocSink for Rec {
    fn set(&self, doc: Value) {
        self.0.lock().unwrap().push(doc);
    }
}

impl Rec {
    pub fn new() -> Arc<Self> {
        Arc::default()
    }
    pub fn count(&self) -> usize {
        self.0.lock().unwrap().len()
    }
    pub fn last(&self) -> Option<Value> {
        self.0.lock().unwrap().last().cloned()
    }
    /// Wait until the latest document satisfies `pred`; panic with the last doc on timeout.
    pub async fn wait(&self, what: &str, pred: impl Fn(&Value) -> bool) -> Value {
        for _ in 0..200 {
            if let Some(d) = self.last().filter(|d| pred(d)) {
                return d;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("timed out waiting for {what}; last doc: {:?}", self.last());
    }
}

/// Documents must never contain null (PROTOCOL §3).
pub fn assert_no_null(v: &Value) {
    match v {
        Value::Null => panic!("null in document"),
        Value::Array(a) => a.iter().for_each(assert_no_null),
        Value::Object(o) => o.values().for_each(assert_no_null),
        _ => {}
    }
}
