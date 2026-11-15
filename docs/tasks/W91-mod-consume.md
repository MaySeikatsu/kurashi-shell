# W91 — Mods read services and call each other from Rust (session 34, K154 step 5; I127, I552; lead)

`ModCtx` registers what a mod provides and offers nothing to read or call. Two mods work around it in QML, against rule 1:
lyrics' views send `lyrics.track` on every track change (so lyrics follow the player only while a view is up), and the
sessions mod publishes `handoff` in its document for a QML surface to relay (`mods/sessions/qml/surfaces/chooser.qml:47`).

## Goal
1. `kurashi-mod-api`: `ModCtx::follow(doc) -> Result<watch::Receiver<Value>, ModError>` — a read-only feed of a document
   the manifest names in `uses` (`doc:<name>`), refcounted like a subscription and held only while the mod's own service
   or job runs (Ma); `ModCtx::caller() -> Caller` with `Caller::call(action, args).await -> Result<Option<Value>,
   ActionError>` for an action named in `uses` (`action:<id>`). Both refuse what the manifest does not name
   (`ModError::NotDeclared`), and the base set (contract.rs `BASE_*`) needs no entry. New `Hooks` methods carry them to
   the daemon (`kurashid/src/native.rs`: the hub's subscription, the action registry's `invoke`).
2. A required use that is not there (the other mod is off, the action not registered) makes the mod **inert with its
   reason** at enable: `mods.uses.missing` with the name, shown on its Settings page and Mods row (Shōjiki); it becomes
   live when the use appears (the registry reconciles on every mods change). An optional use (`?`) is the mod's to handle:
   `follow` answers a feed that says `{available: false}`, `call` answers `Unavailable`.
3. **lyrics**: follows `svc.media` itself; `lyrics.track` and the views' sending go (manifest: `uses = ["doc:svc.media"]`
   stays, now read by the crate). **sessions**: calls `terminal.run` / `terminal.open_dir` itself; `handoff`,
   `sessions.handed`, `sessions.undelivered` and the relay in `chooser.qml` go. **timer**: its end notification through a
   core action instead of its own D-Bus call, if `notify.*` has one that fits; else a CONTRACT-CHANGE row.
4. A host's scope (K38, `kurashid/src/native/hosts.rs` `scope_allows_doc` / `scope_allows_action`) reads the manifest's
   `uses` plus the base set, instead of its fixed list with `svc.clock` added (row 118).
5. `kurashi mod check`: a `uses` entry no view names is no longer noted when the crate follows or calls it (the check
   reads the crate's `follow("…")` / `call("…")` literals for bundled mods).

## Contract
PROTOCOL §2 (the scope's list comes from `uses`), MODS.md "Integration contract" (roll-out step 5: built), fixtures for
the changed `mod.lyrics` and `mod.sessions` shapes, a DECISIONS entry for the removed actions (Breaking in the CHANGELOG).

## Acceptance
`cargo nextest run -p kurashi-mod-api -p kurashid -p kurashi-mod-lyrics -p kurashi-mod-sessions` with new tests: an
undeclared follow or call is refused; a missing required use makes the mod inert with its reason and live again when it
appears; lyrics change with the track with no view up; a session opens in the terminal with no surface mapped.
`frontend/test-mod-contract.sh`, `mods/lyrics/test-lyrics.sh`, `mods/sessions/test/test-sessions.sh` green on niri.
