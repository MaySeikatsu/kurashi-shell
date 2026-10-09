# Card W12-quick-daemon — actions behind the quick settings sections (M7, K24)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K24, `docs/PROTOCOL.md` §8 (`svc.audio`, `svc.network`,
`svc.power` rows — the lead adds the two actions there before this card starts), `crates/kurashid/src/main.rs`
(audio/network registration), `crates/kurashi-audio/src/lib.rs` (`Commands::set_default_sink` exists),
`crates/kurashi-services/src/network.rs`, NetworkManager D-Bus API (`WirelessEnabled` property).

**Owned paths:** `crates/kurashid/src/main.rs` (only the audio + network registration blocks),
`crates/kurashi-services/src/network.rs` (+ tests), `crates/kurashid/tests/quick_actions.rs` (new),
`i18n/{en,ja}/session.toml` (action labels; add keys only), `crates/kurashi-mock/src/{state,documents}.rs` (mock parity).

**Do:** `audio.sink.default {id}` → `Commands::set_default_sink` (unknown id → `invalid`, service not running →
`error.service.not_running` like the other audio actions). `network.wifi {on}` → set NM `WirelessEnabled` on the
system bus; a polkit refusal or no NM → `unavailable` with an i18n key (`error.network.refused`,
`error.network.unavailable`); the document follows from NM's PropertiesChanged (no optimistic write, rule 2).
Mock: both actions change its documents. Also file nothing silently: if `svc.audio` lacks something the UI card
needs (e.g. sink `description`), it is there already — check before adding.

**Acceptance:** `crates/kurashid/tests/quick_actions.rs`: audio with the fake backend (`start_with`) → default sink
changes; network on a private system-bus with a fake NM (copy the pattern of kurashi-services tests) → property set,
document follows; refusal → error key. Mock unit tests for both actions. clippy -D warnings, fmt.
