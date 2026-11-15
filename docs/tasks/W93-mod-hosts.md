# W93 — A mod's own program, in any language (session 34, K155; I576; lead — protocol design first)

Today `host:` needs a linked `NativeMod` (B15), so a mod someone downloads can be views only. K155: a mod with code of
its own outside the tree is a host program the manifest declares.

## Design (write it into PROTOCOL.md and MODS.md first, with fixtures; then build)
1. **Manifest:** `[[host]] name = "main"`, `exec = "tea-host"` (a file in the mod's `bin/`, or a name on `PATH` with the
   capability `exec:<name>`), `args`, `env`, `start = "enabled" | "subscribed" | "action"` (when the daemon starts it;
   default `subscribed`: Ma). The documents it serves (`service:<id>`) and its actions (`[[action]]`) are declared as for
   any mod; nothing undeclared is accepted from it.
2. **Protocol (additive to v1, a scoped connection only):** `{"t":"pub","doc":"mod.tea","data":{…}}` replaces the mod's own
   document (the hub strips `null`, diffs and broadcasts as for any writer; size-limited); `{"t":"serve","actions":["tea.start"]}`
   takes the mod's declared actions; the daemon then sends `{"t":"call","id":"7","action":"tea.start","args":{…}}` (already
   checked against the schema) and waits for `{"t":"done","id":"7","data"?}` or `{"t":"err",…}` with a timeout (an action
   whose host is not running starts it when `start = "action"`, else answers `unavailable` with `mods.host.not_running`).
   Reads and calls outward are the manifest's `uses` (W91's scope).
3. **Supervision:** as K38 — own process group, the scope token, a restart once, `Failed` with the log's path, stop on
   disable; the Mods page shows the host's state and its capabilities before the switch is turned.
4. **Trust:** a host program is the user's code running as the user. The Mods page says so in words before the first
   enable of a mod that has one ("This mod runs a program: …"), names its `uses` and capabilities, and the catalogue
   (W98) carries its hash. No sandbox is promised that is not there; bubblewrap for hosts is a later row.
5. **Templates:** `kurashi mod new --host python|rust|go` writes a host that says hello, publishes one document and
   answers one action, with `kurashi mod check` passing; a small client library is not shipped — the protocol is ten
   lines of NDJSON, shown in MODDING.md.

## Acceptance
A scaffolded Python host mod, enabled in the sandbox: its document appears, `> <its command>` runs its action and the
document changes, an undeclared `pub` or `serve` is refused and logged, killing the host shows `starting` then `ready`
again, disabling stops it; `fixtures/ipc/{client,server}` for `pub`, `serve`, `call`; a suite on niri in the merge set;
MODDING.md's route table says "works today".
