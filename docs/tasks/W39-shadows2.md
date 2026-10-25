# Card W39-shadows2 — every surface follows the shadow vector (I206)

**Why:** W38-shadows (K67) moved Block, SoftShadow, MorphShape, ColumnShape and the bar groups onto `shadow.dx/dy`; the
surfaces below still cast straight down when the direction is not 180° (BACKLOG I206, CONTRACT-CHANGE rows 422, 423).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/shadows.md`; DECISIONS K67; DESIGN-SYSTEM §7 (shadow vector);
BACKLOG I206; `frontend/core/Theme.qml` (`shadowX/Y`, `sinkX/Y`, `shadowAlpha`), `frontend/components/{Block,SoftShadow}.qml`
(the pattern), `frontend/test-shadows.sh`.

**Task:**
1. NotificationCard, LockContent, NotificationCenter, Toasts, PolkitDialog, the ClockView day keys and Settings'
   SheetHost/SectionCard draw their hard shadow at `Theme.sinkX/sinkY` and soft shadows at `shadowX/Y` (× `shadowAlpha`).
2. `settings/core/Theme.qml` gains the same five properties as the shell's Theme (fallbacks = today).
3. `sidebar.style = floating` drew the flush panel in the sandbox: find why (a condition, or a bug) and shoot ColumnShape's
   hard shadow at 135°.
4. Extend `test-shadows.sh`: a `surfaces2` part shooting each surface above at 135° strength 2 and at the defaults
   (defaults must match HEAD pixel for pixel, as W38's `SHADOW_REF` check does).

**Owned paths:** `frontend/components/{NotificationCard,LockContent,PolkitDialog}.qml` (or wherever those live — grep),
`frontend/surfaces/{NotificationCenter,Toasts,PolkitDialog,Lock}.qml` (shadow lines only), `frontend/components/expanded/ClockView.qml`
(day key shadow only), `frontend/surfaces/Sidebar.qml` (floating style only), `settings/core/Theme.qml`,
`settings/components/{SheetHost,SectionCard}.qml`, `frontend/test-shadows.sh` + `frontend/shots/shadows/`.

**Acceptance:** `bash frontend/test-shadows.sh` (all parts incl. `surfaces2`, defaults identical); `test-toasts.sh` washi:calm:top green.

**Contract rows:** CONTRACT-CHANGE rows 440–444 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w39-shadows2 CARGO_BUILD_JOBS=4`; sandbox names `w39-sh2-…`.
Model: haiku (max effort).
