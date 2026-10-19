//! Host processes (K38, MODS.md "Host processes") and the scoped connections they connect with (PROTOCOL §2).
//! A mod's host is a program the daemon starts when the mod asks, supervises (one restart, then `Failed`), and
//! stops on request, on disable and at daemon shutdown. It connects back with a `hello` whose `scope` carries the
//! token the daemon handed it. That connection reaches only the mod's own documents and actions, `theme` and
//! `i18n` (server.rs asks [`scope_allows_doc`] and [`scope_allows_action`]).

use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{Duration, Instant};

use kurashi_ipc::Scope;
use kurashi_mod_api::{HostSpec, HostState};
use rustix::process::{Pid, Signal, kill_process_group};
use tokio::process::Command;
use tokio::runtime::Handle;
use tokio::sync::watch;

use super::{Running, set_running};
use crate::hub::Hub;

/// SIGTERM to a host's group, then SIGKILL after this long if it still lives (MODS.md: 3 s).
const KILL_AFTER: Duration = Duration::from_secs(3);
/// A second unexpected exit within this long is a failure, not another restart (MODS.md: 10 minutes).
const CRASH_WINDOW: Duration = Duration::from_secs(10 * 60);
/// A host's log keeps its last 1 MiB, cut at each start (MODS.md).
const LOG_CAP: u64 = 1024 * 1024;
/// Why a host that stopped twice in a row is `Failed` (an i18n key, MODS.md).
const FAILED_REASON: &str = "mods.host.failed";

/// Where host programs are searched and where a mod's directories are, when they are not the defaults (`PATH`
/// and `$XDG_*_HOME/kurashi`). Set once per process, before a host starts: the daemon never sets it. Tests use
/// it, because the process environment cannot be changed without `unsafe` here.
#[derive(Debug, Clone, Default)]
pub struct HostEnv {
    /// Directories searched before `PATH`.
    pub search: Vec<PathBuf>,
    /// Replaces `$XDG_DATA_HOME/kurashi` as the parent of the mods' data directories.
    pub data: Option<PathBuf>,
    /// Replaces `$XDG_CACHE_HOME/kurashi`.
    pub cache: Option<PathBuf>,
    /// Replaces `$XDG_STATE_HOME/kurashi`.
    pub state: Option<PathBuf>,
}

static HOST_ENV: OnceLock<HostEnv> = OnceLock::new();

/// Sets the host environment of this process. False when one was set already: the first set wins.
pub fn set_host_env(env: HostEnv) -> bool {
    HOST_ENV.set(env).is_ok()
}

fn host_env() -> HostEnv {
    HOST_ENV.get().cloned().unwrap_or_default()
}

/// The directories of one mod (MODS.md "Host processes"): `{data_dir}`, `{cache_dir}`, `{state_dir}`.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ModDirs {
    data: PathBuf,
    cache: PathBuf,
    state: PathBuf,
}

impl ModDirs {
    fn of(mod_id: &str) -> Self {
        let env = host_env();
        let dir = |root: Option<PathBuf>, kind: &str| {
            root.unwrap_or_else(|| crate::xdg_dir(kind)).join(mod_id)
        };
        Self {
            data: dir(env.data, "data"),
            cache: dir(env.cache, "cache"),
            state: dir(env.state, "state"),
        }
    }
}

/// `{mod_dir}`, `{data_dir}`, `{cache_dir}` and `{state_dir}` replaced in a spec's argument or value.
fn expand(text: &str, mod_dir: &Path, dirs: &ModDirs) -> String {
    text.replace("{mod_dir}", &mod_dir.to_string_lossy())
        .replace("{data_dir}", &dirs.data.to_string_lossy())
        .replace("{cache_dir}", &dirs.cache.to_string_lossy())
        .replace("{state_dir}", &dirs.state.to_string_lossy())
}

/// The first executable `name` in the host search directories, then in `PATH` (absolute directories only).
fn find_binary(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH").unwrap_or_default();
    host_env()
        .search
        .into_iter()
        .chain(std::env::split_paths(&path))
        .filter(|dir| dir.is_absolute())
        .map(|dir| dir.join(name))
        .find(|candidate| is_executable(candidate))
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// 128 random bits as hex: a fresh token for every start (MODS.md).
fn new_token() -> std::io::Result<String> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// Opens a host's log for appending, after cutting it to its last [`LOG_CAP`] bytes (MODS.md).
fn open_log(path: &Path) -> std::io::Result<File> {
    let mut f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    let len = f.metadata()?.len();
    if len > LOG_CAP {
        f.seek(SeekFrom::Start(len - LOG_CAP))?;
        let mut tail = Vec::with_capacity(LOG_CAP as usize);
        f.read_to_end(&mut tail)?;
        f.set_len(0)?;
        f.seek(SeekFrom::Start(0))?;
        f.write_all(&tail)?;
    }
    OpenOptions::new().append(true).create(true).open(path)
}

/// Sends `sig` to the process group `pid`: a host leads its own group (MODS.md).
fn signal_group(pid: u32, sig: Signal) {
    if let Some(pid) = i32::try_from(pid).ok().and_then(Pid::from_raw) {
        let _ = kill_process_group(pid, sig);
    }
}

/// A token the daemon issued for a host: whose it is, the host it belongs to, and whether a connection holds it.
struct Issued {
    mod_id: String,
    host: Weak<HostCore>,
    held: bool,
}

/// The tokens of running hosts. Process-wide because the connection handler reaches it without a handle to
/// the mods' state (`Daemon` does not carry one); tokens are random, so two daemons in one process never clash.
static SCOPES: Mutex<BTreeMap<String, Issued>> = Mutex::new(BTreeMap::new());

/// Every host the daemon has made, for [`shutdown_all`].
static CORES: Mutex<Vec<Weak<HostCore>>> = Mutex::new(Vec::new());

fn issue(token: &str, mod_id: &str, host: Weak<HostCore>) {
    let issued = Issued {
        mod_id: mod_id.into(),
        host,
        held: false,
    };
    SCOPES
        .lock()
        .expect("scopes lock")
        .insert(token.into(), issued);
}

fn revoke(token: &str) {
    SCOPES.lock().expect("scopes lock").remove(token);
}

/// A `hello` whose scope is refused: the token is unknown, revoked, for another mod, or held (PROTOCOL §2).
#[derive(Debug, PartialEq, Eq)]
pub struct ScopeRefused;

/// A scoped connection's hold on its host's token. The host is `Ready` while the hold lives; dropping it (the
/// connection closed) makes the host `Starting` again, and the token stays valid for its reconnect.
pub struct ScopeHold {
    token: String,
    host: Weak<HostCore>,
}

impl Drop for ScopeHold {
    fn drop(&mut self) {
        if let Some(entry) = SCOPES.lock().expect("scopes lock").get_mut(&self.token) {
            entry.held = false;
        }
        if let Some(host) = self.host.upgrade() {
            host.disconnected(&self.token);
        }
    }
}

/// Checks the scope of a `hello` (PROTOCOL §2): the token must be one the daemon issued for a running host of
/// `scope.mod_id` and no other live connection holds it. The host is `Ready` from then on.
pub fn connect_scope(scope: &Scope) -> Result<ScopeHold, ScopeRefused> {
    let host = {
        let mut scopes = SCOPES.lock().expect("scopes lock");
        let entry = scopes
            .get_mut(&scope.token)
            .filter(|e| e.mod_id == scope.mod_id && !e.held)
            .ok_or(ScopeRefused)?;
        entry.held = true;
        entry.host.clone()
    };
    if let Some(host) = host.upgrade() {
        host.connected(&scope.token);
    }
    Ok(ScopeHold {
        token: scope.token.clone(),
        host,
    })
}

/// Whether a scoped connection of `mod_id` may subscribe to `doc`: its own documents (`mod.<id>` and
/// `mod.<id>.*`), `theme` and `i18n` (PROTOCOL §2).
pub fn scope_allows_doc(mod_id: &str, doc: &str) -> bool {
    doc == "theme"
        || doc == "i18n"
        || doc == format!("mod.{mod_id}")
        || doc.starts_with(&format!("mod.{mod_id}."))
}

/// Whether a scoped connection of `mod_id` may invoke `action`: the mod's own (`<id>.*`) (PROTOCOL §2).
pub fn scope_allows_action(mod_id: &str, action: &str) -> bool {
    action.starts_with(&format!("{mod_id}."))
}

/// Stops every host the daemon runs, at daemon shutdown (MODS.md): SIGTERM now, then waits up to the kill
/// deadline for the processes to end (the killer of each one sends SIGKILL at that deadline).
pub async fn shutdown_all() {
    let cores: Vec<Arc<HostCore>> = CORES
        .lock()
        .expect("cores lock")
        .iter()
        .filter_map(Weak::upgrade)
        .collect();
    for core in &cores {
        core.stop();
    }
    let deadline = Instant::now() + KILL_AFTER + Duration::from_millis(500);
    while Instant::now() < deadline && cores.iter().any(|c| c.still_running()) {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// What a host needs from the mod it belongs to, and from the daemon (see `Native::activate`).
pub(super) struct HostParams {
    pub mod_id: String,
    pub name: String,
    pub spec: HostSpec,
    pub mod_dir: PathBuf,
    /// The state the mod's handle reads; the daemon writes it here.
    pub state: Arc<watch::Sender<HostState>>,
    pub running: Arc<Running>,
    pub hub: Weak<Hub>,
    pub runtime: Handle,
}

/// One host of one enabled mod. The mod's handle starts and stops it; its state goes to `state`.
pub(super) struct HostCore {
    me: Weak<HostCore>,
    mod_id: String,
    name: String,
    spec: HostSpec,
    mod_dir: PathBuf,
    dirs: ModDirs,
    state: Arc<watch::Sender<HostState>>,
    running: Arc<Running>,
    hub: Weak<Hub>,
    runtime: Handle,
    inner: Mutex<Inner>,
}

#[derive(Default)]
struct Inner {
    /// Counts the processes started; the reaper of an older one changes nothing.
    generation: u64,
    /// The program's resolved path, for the restart.
    bin: Option<PathBuf>,
    /// The live process, if one runs.
    run: Option<Run>,
    /// When the last unexpected exit happened.
    last_exit: Option<Instant>,
    /// The exited flag of the process that `stop` ended, until it has exited.
    stopping: Option<Arc<AtomicBool>>,
}

/// A live process: its token, its group (its pid), and the flag its reaper sets when it ends.
struct Run {
    generation: u64,
    token: String,
    pid: u32,
    exited: Arc<AtomicBool>,
}

impl HostCore {
    pub(super) fn new(p: HostParams) -> Arc<Self> {
        let dirs = ModDirs::of(&p.mod_id);
        let core = Arc::new_cyclic(|me| Self {
            me: me.clone(),
            mod_id: p.mod_id,
            name: p.name,
            spec: p.spec,
            mod_dir: p.mod_dir,
            dirs,
            state: p.state,
            running: p.running,
            hub: p.hub,
            runtime: p.runtime,
            inner: Mutex::default(),
        });
        let mut cores = CORES.lock().expect("cores lock");
        cores.retain(|w| w.strong_count() > 0);
        cores.push(Arc::downgrade(&core));
        core
    }

    /// Starts the process unless one runs (idempotent, MODS.md). A host that is `Missing` or `Failed` is tried again.
    pub(super) fn start(self: &Arc<Self>) {
        let active = {
            let mut inner = self.inner.lock().expect("host lock");
            if inner.run.is_some() {
                return;
            }
            inner.last_exit = None;
            let state = match find_binary(&self.spec.binary) {
                None => HostState::Missing,
                Some(bin) => {
                    inner.bin = Some(bin.clone());
                    self.spawn(&mut inner, &bin)
                }
            };
            let active = state.is_running();
            self.state.send_replace(state);
            active
        };
        self.announce(active);
    }

    /// Stops the process (MODS.md): SIGTERM to its group now, SIGKILL after [`KILL_AFTER`] if it still lives. Its
    /// token is revoked and the state is `Off`.
    pub(super) fn stop(&self) {
        let run = {
            let mut inner = self.inner.lock().expect("host lock");
            let run = inner.run.take();
            if let Some(run) = &run {
                inner.stopping = Some(run.exited.clone());
            }
            self.state.send_replace(HostState::Off);
            run
        };
        if let Some(run) = run {
            revoke(&run.token);
            signal_group(run.pid, Signal::TERM);
            let (pid, exited) = (run.pid, run.exited);
            self.runtime.spawn(async move {
                tokio::time::sleep(KILL_AFTER).await;
                if !exited.load(Ordering::SeqCst) {
                    signal_group(pid, Signal::KILL);
                }
            });
        }
        self.announce(false);
    }

    /// Whether a process `stop` ended has not exited yet.
    fn still_running(&self) -> bool {
        let inner = self.inner.lock().expect("host lock");
        inner
            .stopping
            .as_ref()
            .is_some_and(|flag| !flag.load(Ordering::SeqCst))
    }

    /// Starts a process now: `Starting` on success, `Failed` when it cannot be started.
    fn spawn(&self, inner: &mut Inner, bin: &Path) -> HostState {
        match self.launch(inner, bin) {
            Ok(()) => HostState::Starting,
            Err(detail) => HostState::Failed {
                reason: FAILED_REASON.into(),
                detail,
            },
        }
    }

    fn launch(&self, inner: &mut Inner, bin: &Path) -> Result<(), String> {
        let me = self.me.upgrade().ok_or("the host is gone")?;
        let token = new_token().map_err(|e| format!("token: {e}"))?;
        for dir in [&self.dirs.data, &self.dirs.cache, &self.dirs.state] {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        let log = self.log_path();
        let out = open_log(&log).map_err(|e| format!("{}: {e}", log.display()))?;
        let err = out.try_clone().map_err(|e| e.to_string())?;
        // A program, not a shell line: the arguments are passed as they are (MODS.md).
        let mut cmd = Command::new(bin);
        cmd.args(
            self.spec
                .args
                .iter()
                .map(|a| expand(a, &self.mod_dir, &self.dirs)),
        )
        .stdin(Stdio::null())
        .stdout(Stdio::from(out))
        .stderr(Stdio::from(err))
        .process_group(0);
        for (key, value) in &self.spec.env {
            cmd.env(key, expand(value, &self.mod_dir, &self.dirs));
        }
        cmd.env("KURASHI_SOCKET", kurashi_core::default_socket_path())
            .env("KURASHI_SCOPE_MOD", &self.mod_id)
            .env("KURASHI_SCOPE_TOKEN", &token);
        let child = cmd.spawn().map_err(|e| format!("{}: {e}", bin.display()))?;
        let pid = child.id().ok_or("the host has no process id")?;

        inner.generation += 1;
        let generation = inner.generation;
        let exited = Arc::new(AtomicBool::new(false));
        issue(&token, &self.mod_id, self.me.clone());
        inner.run = Some(Run {
            generation,
            token,
            pid,
            exited: exited.clone(),
        });
        self.runtime.spawn(async move {
            let mut child = child;
            let status = child.wait().await;
            exited.store(true, Ordering::SeqCst);
            me.exited(generation, status);
        });
        Ok(())
    }

    /// The process `generation` ended without a `stop`: restarted once; a second exit within [`CRASH_WINDOW`] is `Failed`.
    fn exited(self: &Arc<Self>, generation: u64, status: std::io::Result<ExitStatus>) {
        let active = {
            let mut inner = self.inner.lock().expect("host lock");
            let Some(run) = inner.run.take_if(|r| r.generation == generation) else {
                return;
            };
            revoke(&run.token);
            let ended = match status {
                Ok(s) => s.to_string(),
                Err(e) => e.to_string(),
            };
            let again = inner.last_exit.is_some_and(|t| t.elapsed() < CRASH_WINDOW);
            let state = if again {
                HostState::Failed {
                    reason: FAILED_REASON.into(),
                    detail: format!("{ended}; log {}", self.log_path().display()),
                }
            } else {
                inner.last_exit = Some(Instant::now());
                match inner.bin.clone() {
                    Some(bin) => self.spawn(&mut inner, &bin),
                    None => HostState::Missing,
                }
            };
            let active = state.is_running();
            self.state.send_replace(state);
            active
        };
        self.announce(active);
    }

    /// A scoped connection with `token` said hello: the process is `Ready`.
    fn connected(&self, token: &str) {
        let inner = self.inner.lock().expect("host lock");
        if inner.run.as_ref().is_some_and(|r| r.token == token) {
            self.state.send_replace(HostState::Ready);
        }
    }

    /// The connection with `token` closed while the process lives: `Starting` again, until it reconnects.
    fn disconnected(&self, token: &str) {
        let inner = self.inner.lock().expect("host lock");
        if inner.run.as_ref().is_some_and(|r| r.token == token) {
            self.state.send_replace(HostState::Starting);
        }
    }

    fn log_path(&self) -> PathBuf {
        self.dirs.state.join(format!("host-{}.log", self.name))
    }

    /// Tells the `mods` document whether the mod runs a host now (K33: `running_reasons`).
    fn announce(&self, active: bool) {
        if self.running.set_host(&self.mod_id, &self.name, active)
            && let Some(hub) = self.hub.upgrade()
        {
            let _ = hub.update("mods", None, |d| {
                set_running(d, &self.mod_id, self.running.reasons(&self.mod_id));
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scopes_reach_the_mods_own_documents_and_actions_only() {
        assert!(scope_allows_doc("webdock", "mod.webdock"));
        assert!(scope_allows_doc("webdock", "mod.webdock.pins"));
        assert!(scope_allows_doc("webdock", "theme"));
        assert!(scope_allows_doc("webdock", "i18n"));
        assert!(!scope_allows_doc("webdock", "mod.webdockx"));
        assert!(!scope_allows_doc("webdock", "mod.weather"));
        assert!(!scope_allows_doc("webdock", "mods"));
        assert!(!scope_allows_doc("webdock", "svc.network"));

        assert!(scope_allows_action("webdock", "webdock.host.loaded"));
        assert!(!scope_allows_action("webdock", "webdockx.open"));
        assert!(!scope_allows_action("webdock", "mod.enable"));
        assert!(!scope_allows_action("webdock", "cfg.set"));
    }

    #[test]
    fn expansion_names_the_mod_and_its_directories() {
        let dirs = ModDirs {
            data: PathBuf::from("/d/webdock"),
            cache: PathBuf::from("/c/webdock"),
            state: PathBuf::from("/s/webdock"),
        };
        assert_eq!(
            expand(
                "{mod_dir}/host/shell.qml {data_dir}|{cache_dir}|{state_dir}",
                Path::new("/m/webdock"),
                &dirs
            ),
            "/m/webdock/host/shell.qml /d/webdock|/c/webdock|/s/webdock"
        );
    }

    #[test]
    fn a_token_is_refused_when_unknown_or_for_another_mod() {
        issue("0123", "webdock", Weak::new());
        let other = Scope {
            mod_id: "weather".into(),
            token: "0123".into(),
        };
        assert!(connect_scope(&other).is_err());
        let unknown = Scope {
            mod_id: "webdock".into(),
            token: "ffff".into(),
        };
        assert!(connect_scope(&unknown).is_err());
        revoke("0123");
    }
}
