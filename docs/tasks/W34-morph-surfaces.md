# Card W34-morph-surfaces — launcher, notification centre and toasts out of the bar (one morph language, part 3)

**User (session 13):** "I like how the dynamic island animates … other extended surfaces should behave the same and also
get a similar merging animation going on into the bar." Keep calm and lively.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; **`docs/ux/motion.md`** (rows launcher, notification centre,
toasts; profiles); `docs/ux/launcher.md`, the notifications part of `docs/ux/island.md`; DECISIONS K16, K42;
`frontend/surfaces/{Launcher,NotificationCenter,Toasts}.qml`, `frontend/components/NotificationCard.qml`,
`frontend/components/island/{MorphShape,IslandGeom}.qml` (read-only), `frontend/components/Relief.qml` header,
`frontend/test-launcher.sh`, the notification tests in `frontend/test-real.sh`.

**Task:**
1. **Launcher:** grows out of the island pill (IslandGeom gives its rect per output) — or its bar button when the bar
   has one — as one MorphShape with the liquid neck at the bar's edge, content cut and faded in late; folds back on
   close. Its window must cover the bar strip above the card while the shape is out (as the Stage does, K16: only then).
2. **Notification centre:** grows out of the notifications face / bell the same way.
3. **Toasts bud off the bar:** a new toast's shape drops out of the bar under the island with a neck that thins and
   detaches (a drip), then stands as a free card; a swipe/dismiss flicks it away (not back into the bar); a stack moves
   with springs. Calm vs lively (squash on the detach) from tokens only; `none` cuts.
4. **I148:** toasts stay hidden while the right sidebar is open on that output (`runtime.ui.sidebar`), and come back
   after it closes.
5. **Tests/shots:** `test-launcher.sh` + a toast/notification-centre test (extend `test-real.sh` or a new
   `frontend/test-toasts.sh`): mid-open shots at 40/120/250 ms, calm and lively, washi/sekai/kami, top and bottom bar;
   I148 check → `frontend/shots/morph/{launcher,notifications,toast}-*`. `test-texture.sh`, `test-pen.sh` stay green.

**Owned paths:** `frontend/surfaces/{Launcher,NotificationCenter,Toasts}.qml`, `frontend/components/NotificationCard.qml`,
`frontend/components/launcher/**`, `frontend/test-launcher.sh`, `frontend/test-toasts.sh` (new), the notification
steps you add to tests, `frontend/shots/morph/{launcher,notifications,toast}-*`, `frontend/shots/launcher/**`.
Read-only: MorphShape, IslandGeom (W34-morph-stage owns them — a needed API → CONTRACT-CHANGE row; keep using today's
API). Not Stage/Sidebar/Theme.qml/crates.

**Acceptance:** the launcher and toast tests exit 0 with their shots; idle 0 frames; the suites above green.

**Env:** `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/lead/debug`; no cargo. Sandbox names `w34-surf-…`.
Machine A (`KURASHI_RENDER_NODE=/dev/dri/renderD128` for test-launcher). Four agents share the machine.
