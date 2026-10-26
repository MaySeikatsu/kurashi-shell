# Card W43-frame — the screen frame, and the bar as its band (K71; docs/ux/frame.md)

**Why:** the user's draft (images 1, 2, 8) asks for a frame round each screen in the shell's own material that joins the
bar into one sheet and, by default, keeps windows inside it.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71 (geometry rules, the one-holder rule), K59 (texture,
TileSheet), K62 (pen), K67 (shadows); `docs/ux/frame.md` (whole); PROTOCOL §3.1 and
`fixtures/ipc/server/snap_runtime_layout.json`; `frontend/core/ShellLayout.qml` (the reader — use it, do not read the document
yourself); `frontend/surfaces/ScreenCorners.qml` (the pattern: static Shapes, click-through, no surface while off);
`frontend/surfaces/Bar.qml` (its exclusive zone, the rule segments `bg`, the strip's material Loader, the pen rule);
`frontend/components/TileSheet.qml`, `Relief.qml`; `frontend/shell.qml`.

**Task:**
1. `frontend/surfaces/Frame.qml`: per output, only while `ShellLayout.of(output).frame.on` — four strips (top and bottom span
   the width; left and right the height between them), each `band + radius` deep, drawing the band and the inner corner
   fillets (`frame.radius`) in `Theme.panel`; click-through (`mask: Region {}`), keyboard none, layer Top, namespace
   `kurashi-frame`, static (0 frames idle). The strip whose edge's `holder` is `frame` sets `exclusiveZone` to
   `edges.<e>.reserve`; the others `ExclusionMode.Ignore`. Fullscreen (a fullscreen window on that output, from
   `svc.workspaces` if it says so — check what niri reports; if nothing, report): the strips step aside.
2. **Chrome:** line chrome rules the band's inner edge (and round the fillets) in the outline; the bar's rule runs into it
   with no seam — Bar.qml's rule segments end where the frame's rule takes over (flush top bar: the rule turns down the
   fillet). Pen chrome: the frame's rule by the pen (`PenOutline`/`PenInk` as Bar's `rulePen`). Flat/keycap/soft: a plain
   sheet. Texture: the band takes the material with the bar's tiles **in screen coordinates** so the grain continues
   across bar → band (washi paper, sekai). Light: the relief follows the light like the bar's.
3. **Bar.qml:** read `ShellLayout.edgeOf(output, edge)`: when the frame holds the edge (`holder != "bar"`), the bar uses
   `ExclusionMode.Ignore` and stands at `inset`; the floating draw (`draw == "floating"`): inset by `band + gap` on its
   edge and from the bands beside it, every corner rounded (image 8) — the bar's floating look only, not visibility or
   zones (W44). Keep everything else of Bar.qml as it is (W44 owns zones and multi-bar).
4. `frontend/shell.qml`: a `Variants` of `Frame` per screen (LazyLoader on the frame being on, like ScreenCorners).
5. A test `frontend/test-frame.sh` (sandbox, mock with `KURASHI_MOCK_LAYOUT` staging — the sandbox's outputs are not
   named `DP-1`, so stage the `"*"` entry of each staged file: frame off / on with top bar / on with
   floating bottom bar / on with no bar; reserve on/off with a test window — the window's position proves the zone):
   shots in `frontend/shots/frame/<decor>/` for washi, sekai, glass, win95, terminal (light + dark for washi).
   Verify the zone arithmetic on niri too if the sandbox can nest niri (`I207` notes it may not draw layer surfaces —
   then report and say what was verified where).
6. BENCH: per-output PSS with the frame on vs off (back-to-back pairs), idle frames 0.

**Owned paths:** `frontend/surfaces/Frame.qml` (new), `frontend/surfaces/Bar.qml` (exclusive zone, inset/floating geometry,
rule segments only), `frontend/shell.qml` (the Frame Variants only), `frontend/core/ShellLayout.qml` (fixes only),
`frontend/test-frame.sh` (new), `frontend/shots/frame/**`, `docs/BENCH.md` (your entry). Not BarConfig.qml and not the existing `frontend/test-*.sh` (W43-layout renames keys in those).

**Acceptance:** `frontend/test-frame.sh` passes with the shots listed; a window in the sandbox starts inside the band with
reserve on and under it with reserve off; frame off = no `kurashi-frame` surface (check with the sandbox's layer list);
idle frames 0; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 490–499 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w43-frame
CARGO_BUILD_JOBS=4`; sandbox names `w43-frame-…`. The daemon side of `runtime.layout` lands with W43-layout in parallel:
code against the mock + fixture. Model: opus.
