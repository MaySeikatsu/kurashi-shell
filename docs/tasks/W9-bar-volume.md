# Card W9-bar-volume — the bar's volume slider never shows a value that is not in effect (B2)

**Read first:** `docs/tasks/README.md` (common rules), `docs/BACKLOG.md` row B2, `frontend/surfaces/Bar.qml`
(the two `Slider` blocks), `frontend/components/Slider.qml`, `frontend/components/faces/VolumeFace.qml`
(how the island face already shows "unavailable"/"muted"), `i18n/{en,ja}/frontend.toml`, `frontend/test-real.sh`.

**Problem:** with no audio server, `svc.audio` is `{available:false}` and the bar slider draws 0 % (Bar
reads `audio.volume ?? 0`): a value that is not in effect (CLAUDE.md rule 2, Shōjiki). Same before the
first snapshot arrives (no document yet). A muted sink still shows its level as if audible.

**Owned paths:** `frontend/surfaces/Bar.qml` (only the slider blocks and the `audio`/`daemonVolume`
properties), `frontend/components/Slider.qml`, `i18n/{en,ja}/frontend.toml` (add keys only),
`frontend/test-volume.sh` (new). NOT `Island.qml`, `components/faces/**`, `shell.qml`, the mock.

**Do:**
- No document yet, or `available === false`: the slider shows no level (no fill, no knob), is inert
  (no pointer/keyboard input, not in the Tab chain) and dimmed (`Theme.dim`), with a small "⊘" glyph and
  accessible name from a new key `frontend.volume.unavailable` (en "no audio", ja "音声なし").
  Wheel over it sends nothing.
- `muted === true`: the level stays visible but drawn in `Theme.dim` (as VolumeFace does), accessible
  name gets `frontend.volume.muted`.
- Both layouts (horizontal and vertical bar). Keep the Slider's optimistic drag/key logic untouched for
  the available case. Token colours only (rule 4); no new animations without a visibility gate (rule 5).

**Acceptance:** `frontend/test-volume.sh` (model it on `frontend/test-real.sh`; run inside `nix develop`;
use `KURASHI_BIN_DIR` with prebuilt binaries from `tools/bench/bin/` to avoid compiling): start the real
`kurashid` in a sandbox with **no** pulse server (its `svc.audio` is `available:false`) → grim
screenshot of the bar's right end, then assert (python, pixel check) that no accent-coloured fill pixels
exist in the slider rect; then run against `kurashi-mock` (volume 0.5, available) → fill present.
Save the screenshots under `frontend/shots/volume/` (gitignored dir is fine) and describe them in your report.
On machine B export `KURASHI_RENDER_NODE=/dev/dri/renderD129`. `timeout` everything.
