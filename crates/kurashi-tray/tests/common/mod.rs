//! Private bus + recording sink. Nothing here ever touches the user's real session/system bus.
#![allow(dead_code)]

use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_services::DocSink;
pub use kurashi_testkit::TestBus;
use serde_json::Value;

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
