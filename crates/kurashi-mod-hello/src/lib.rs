//! The test native mod (K26, K28). Its manifest lives under kurashid's test data only, never in `mods/`:
//! it exists so the native-mod mechanism is exercised end to end (`crates/kurashid/tests/native_mods.rs`).
//! It registers each hook once: a service, actions, an island face, a choice source for its `greeting`
//! setting. Its slot contribution and its panel are declared in the manifest and need no code here.

use kurashi_mod_api::{Choice, FaceSpec, ModCtx, ModError, NativeMod};
use serde_json::{Value, json};

pub struct Hello;

fn greeting_of(greeting: Option<Value>) -> Value {
    greeting.unwrap_or_else(|| json!("hi"))
}

/// The greetings `mods.hello.greeting` may take (K28 (3)).
fn greetings() -> Vec<Choice> {
    vec![
        Choice::new("hi", "Hi"),
        Choice::new("hello", "Hello"),
        Choice::new("yo", "Yo"),
    ]
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
        // The island face (K24), relevance-driven: raised and cleared through its own actions.
        let face = ctx.face(
            "hello",
            FaceSpec {
                transient: false,
                ttl_s: 0,
            },
        )?;
        let clear = face.clone();
        ctx.action("hello.raise", "action.hello.raise", move |args| {
            let relevance = args["relevance"].as_u64().map_or(50, |r| r.min(100) as u8);
            face.raise(relevance);
            async { Ok(None) }
        })?;
        ctx.action("hello.clear", "action.hello.clear", move |_| {
            clear.clear();
            async { Ok(None) }
        })?;
        ctx.choices("hello.greetings", greetings)?;
        Ok(())
    }
}
