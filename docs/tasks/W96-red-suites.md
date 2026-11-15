# W96 — The six suites that are red on `main` (session 34, B145; the user: fix them, then into the merge set)

Run alone on `main` (862f5375) and on the branch, session 34. For each: is it the product or the suite? Fix that, three
green runs alone, then add it to `MERGE_SET` in `tools/test-suites.sh`.

| Suite | Result | First look |
|---|---|---|
| `mods/timer/test-timer.sh` | 49 of 89: clicks on the glance and the panel's rows do nothing (start, pause, resume, +1 min, stop), in every look | the pointer's coordinates against the panel's geometry (a layout change since the suite was written?) or the panel's rows not taking the click: open the panel on niri and click by hand through `niri-sandbox.sh click` |
| `mods/sysmon/test-states.sh` | 2 findings: "End on the culprit recorded no TERM", "the refused End was not shown as refused" | `sysmon.process.term` through the panel's menu; the capability `proc:signal`; the sandbox's stub process |
| `mods/calendar/test-calendar.sh` | 26 of 27: "sekai: Escape in the details leaves the card open" | Escape's handling in the details view under the sekai look only |
| `mods/terminal/test/test-terminal.sh` | "the card came to rest before its text", a different look each run | a race between the card's rest and the host's first frame (W85's stills): wait for the condition (W55) or a real flash of an empty card |
| `frontend/test-launcher.sh` | branch: 82 of 83 (`>settings bar lists Settings: Bar` — the schema's page is `layout`); `main`: 76 of 83 (thumbnails of image rows) | the suite's page name; the thumbnail checks need the image decoder the dev shell has now |
| `mods/webdock/test/test-dock.sh` | "bar widget: a click asks for the dock's card", "growth: 20 reveal/hide cycles add at most 1 MiB" (5–6.6 MiB), and the cost check at its line (I582) | the widget's click since W72's bar card; the growth is W90's kind of question |

Also from W89's baseline (I579): `test-media`, `mods/lyrics/test-lyrics.sh` need example binaries the runner does not
build; `test-modqml`, `test-mods-live` need `--features test-mods`; `test-volume`, `test-tray-bt`, `test-shadows` fail on
the base. A `# needs:` line the runner reads (`example:<name>`, `feature:<name>`), then the same treatment.

## Acceptance
Each suite green three times alone and once in `just suites`; `tools/suites-known-failing.txt` no longer needed for B92
either if `quick-modules` is fixed here (its race is the same kind). The merge set's wall time is noted before and after
(I544 stays its own work).
