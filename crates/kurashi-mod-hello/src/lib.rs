//! The test native mod (K26). Its manifest lives under kurashid's test data only, never in `mods/`:
//! it exists so the native-mod mechanism is exercised end to end (`crates/kurashid/tests/native_mods.rs`).

use kurashi_mod_api::{ModCtx, ModError, NativeMod};
use serde_json::{Value, json};

pub struct Hello;

fn greeting_of(greeting: Option<Value>) -> Value {
    greeting.unwrap_or_else(|| json!("hi"))
}

impl NativeMod for Hello {
    fn id(&self) -> &'static str {
        "hello"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let initial =
            json!({"available": true, "greeting": greeting_of(ctx.settings().get("greeting"))});
        ctx.service("hello", initial, |publish, mut settings| async move {
            // The greeting in effect, now and after every change of the setting.
            loop {
                publish(
                    json!({"available": true, "greeting": greeting_of(settings.get("greeting"))}),
                );
                if !settings.changed().await {
                    break;
                }
            }
        })?;
        ctx.action("hello.ping", "action.hello.ping", |_| async {
            Ok(Some(json!({"pong": true})))
        })?;
        Ok(())
    }
}
