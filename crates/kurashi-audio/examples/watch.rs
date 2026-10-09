//! Read-only smoke check: prints `svc.audio` documents from the real server for 10 s.
//! Never sends a command.

use std::sync::Arc;
use std::time::Duration;

use kurashi_services::DocSink;

struct Print;
impl DocSink for Print {
    fn set(&self, doc: serde_json::Value) {
        println!("{doc}");
    }
}

fn main() {
    let (handle, _commands) = kurashi_audio::start(Arc::new(Print));
    std::thread::sleep(Duration::from_secs(10));
    drop(handle);
}
