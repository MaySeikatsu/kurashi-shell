# Card W42-shadows3 — the last straight-down shadows (K67; I206, I210)

**Why:** K67: shadows fall along `theme.material.shadow_angle` (or away from the light). W38/W39 moved most surfaces onto the
shadow vector; these still cast straight down at an angle ≠ 180: SessionMenu, KeyClock, PhoneFrame, the web dock's
HostButton and WebCard (Card.qml / Box.qml), and Settings' Button. The lead made the three shadow rows inert under flat and
line chrome (schema `requires`, row 423; on `feat/w42-contracts`, merged before you start).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K45, K67; DESIGN-SYSTEM "shadow vector" paragraph; how
W39-shadows2 did it: `frontend/components/NotificationCard.qml`, `frontend/surfaces/Toasts.qml`, `settings/components/SectionCard.qml`,
`frontend/core/Theme.qml` / `settings/core/Theme.qml` (`sinkX/sinkY`, `shadowX/shadowY`), `frontend/components/SoftShadow.qml`;
the test `frontend/test-shadows.sh` (or wherever W39 put it — grep `shadow_angle` in `frontend/` tests).

**Task:**
1. Each surface above draws its hard shadow at `Theme.sinkX/sinkY` and its soft one at `shadowX/shadowY` (the same
   expressions as the done surfaces; pressed states sink along the same vector). Find any other straight-down shadow left
   (`grep -rn "y: .*chrome.shadow\|shadowOffset\|verticalOffset"` across `frontend/ settings/ mods/`) and list it; fix it if
   inside owned paths.
2. The test: angle 135 and 225 under keycap and soft chrome, one shot per surface, the shadow on the expected side. Tighten
   `same_px`'s blob tolerance (80×30 lets an 80 px sliver pass, I210) to what the surfaces need, and say what you chose.
3. Settings: under flat and under line chrome the three shadow rows show inert with the generated reason (row 423) — one
   screenshot each, en and ja.
4. The intermittent idle burst (49 commits in 5 s with the launcher open at rest, test-toasts, once): try to reproduce
   (10 runs); report the count either way.

**Owned paths:** `frontend/surfaces/SessionMenu.qml`, the KeyClock and PhoneFrame components (grep), `mods/webdock/host/HostButton.qml`,
`mods/webdock/qml/Card.qml`, `mods/webdock/qml/Box.qml`, `settings/components/Button.qml` (or the Settings button component),
the shadow test script and its helpers. Nothing in Theme.qml or the schema: request it.

**Acceptance:** the shadow test passes for every listed surface at 135/225 under keycap and soft; at 180 pixel-identical to
before (0 strong pixels); the inert screenshots; `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 465–469 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w42-shadows3 CARGO_BUILD_JOBS=4`; sandbox names `w42-shadows3-…`.
Model: haiku (max effort).
