# Polkit authentication dialog — UX brief (K47 (5), card W23-auth-media)
Status: v1 (W23). Functional and UX tracked separately in PROGRESS.

## Job
When a program asks the system for a privileged action (`pkexec`, NetworkManager, udisks, a package manager, systemd),
polkit asks the session's **authentication agent** to confirm who the user is. Without an agent the request fails or
hangs; that is the first thing people miss when they leave GNOME/KDE or a Quickshell shell. The dialog says what is
asked, by whom, and takes the password — nothing else. It must never look like something a web page could fake, never
keep the password, and never stay up after the flow ended.

## How others do it
- **GNOME Shell**: a system-modal dialog in the shell itself, a dimmed screen behind; a lock icon, the title
  "Authentication Required", the action's message, the user's avatar and name (a drop-down when several admins may
  answer), the password field, Cancel/Authenticate. A wrong password shakes the dialog and says "Sorry, that didn't work.
  Please try again." Escape cancels. The field is busy (spinner) while PAM checks.
- **KDE Plasma** (polkit-kde-agent-1): a separate window, "Authentication Required", the message, the identity
  combobox, a "Details" expander (action id, vendor), password field, OK/Cancel; wrong password: an inline error.
- **COSMIC**: a layer-shell dialog with a scrim on every output, like GNOME's; identity list when several.
- **macOS**: the system sheet "<App> wants to make changes. Enter your password to allow this." with user name and
  password, Cancel/OK; the wrong password shakes the sheet.
- **Windows UAC**: the secure desktop dims everything; the app's name and publisher; Yes/No or credentials.
- **DankMaterialShell** (`Services/PolkitService.qml`, `Modals/PolkitAuthContent.qml`): Quickshell's `PolkitAgent`; a
  modal with title, the message, `supplementaryMessage` (error colour when `supplementaryIsError`), a password field
  (echo follows `responseVisible`, with a show toggle), Cancel/Authenticate, busy while checking, "Authentication failed
  - try again" under the field on `authenticationFailed`; it selects the *current user* among several identities.
- **illogical-impulse** (`services/PolkitService.qml`, `modules/ii/polkit/PolkitContent.qml`): a full-screen overlay
  per output with a fading scrim, a centred dialog (icon, "Authentication", the message with its trailing dot cut,
  the prompt as placeholder — "Password" when the prompt is empty), Esc cancels, input disabled until polkit asks again.

**Taken:** the GNOME/COSMIC shape (a scrim, one centred card on the focused output, keyboard exclusive), DMS's flow
handling (current user chosen among several identities; busy while checking; the supplementary message; failure under
the field) and ii's prompt clean-up (trailing `:` and `.` dropped, "Password" when polkit sends no prompt), the
lock screen's shake (`LockContent.qml`) for a wrong password. **Not taken:** a scrim on every output (one output is
enough to say "the system is asking"; the others stay usable for reading what was asked about), avatars (no avatar
service yet), a "Details" expander (the action id is in the accessible description and the log, not on screen).

## Design
- **Surface** `frontend/surfaces/PolkitDialog.qml`: the `PolkitAgent` lives for the shell's lifetime (it must, to be
  registered); the window exists **only while a flow is up** (a Loader on `agent.flow`), on the overlay layer of the
  focused output, keyboard **exclusive**, a scrim over the whole output (black at 40 %, the chrome has no scrim token
  yet: contract row), the card centred.
- **Card** (a `Block`, 420 px): a lock icon in a tonal circle, the title "Authentication required", the message (as
  polkit sends it, trailing dot dropped), then the identity — "as <user>" — or, when several identities may answer, a
  row of chips (one per identity, the selected one filled; the current user is chosen first, as DMS does). The field
  (the lock screen's): placeholder = the cleaned prompt; echo = dots unless `responseVisible`; busy (dimmed, read-only,
  "Checking…") between submit and polkit's answer. Under it: the supplementary message (error colour when it is one),
  or after a failure "That password did not work. Try again." with the shake. Buttons: Cancel, Authenticate (primary;
  disabled while busy or empty).
- **Keys**: Return submits, Escape cancels (from anywhere in the card), Tab moves field → chips → Cancel →
  Authenticate. The field has focus on open and again after a failure (cleared).
- **Daemon**: `ui.polkit {active: true}` when a flow starts, `{active: false}` when it ends (success, cancel, failure
  that ends the flow, or the surface going away). The island and the Stage read `runtime.ui.polkit` to stay out of the
  way (later card: they are not this card's paths).
- **Password handling**: the text goes from the TextInput to `flow.submit()` in one call stack and the field is cleared
  first (as the lock screen does, K2); nothing is logged, nothing is bound to a property that outlives the call.

## States
| State | Flow | Card |
|---|---|---|
| no request | `agent.flow` null | no window at all (0 surfaces, 0 frames) |
| asking | `isResponseRequired` | field focused, Authenticate enabled once something is typed |
| checking | submitted, `isResponseRequired` false | field dimmed and read-only, "Checking…", buttons: Cancel only |
| wrong password | `authenticationFailed` | shake, "That password did not work. Try again.", field cleared and focused |
| info / error from PAM | `supplementaryMessage` (`supplementaryIsError`) | the message under the field (error colour when it is one) |
| several identities | `identities.length > 1` | identity chips; switching restarts the request (polkit's rule), not a failure |
| cancelled / succeeded | `isCompleted` | the window goes away; `ui.polkit {active:false}` |
| no agent | registration failed (another agent, no polkitd) | nothing shown; the result is logged once (`polkit: agent registered` / `not registered`) |
| daemon away | — | the dialog still works (the flow is Quickshell's); `ui.polkit` is simply not delivered |

## Fit
Overlay layer like the launcher; it wins over the launcher and the Stage (exclusive keyboard). The lock screen is above
everything (session lock), so a request during lock waits behind it. Multi-output: the focused output, latched for the
flow. Motion: the card fades and rises in (`Theme.stdMs`), the shake uses the lock screen's steps; under motion none,
nothing moves. Budget: idle = no window, 0 frames; the agent is a D-Bus object only.

## Definition of done
- [x] dialog: message, identity, password (echo per `responseVisible`), Authenticate/Cancel, Escape cancels
- [x] wrong password: shake + message + retry; busy while checking
- [x] identity chips when several; current user first
- [x] `ui.polkit {active}` on start and end; `runtime.ui.polkit` in kurashid and the mock
- [x] every decor styles it (Block, Icon, tokens); shots under sekai and none
- [x] i18n en + ja (`i18n/*/polkit.toml`)
- [ ] the island and the Stage step aside while `runtime.ui.polkit` (their cards)
- [ ] a real `pkexec` round trip in a sandbox with its own polkitd (no system bus in the sandbox; contract row)
