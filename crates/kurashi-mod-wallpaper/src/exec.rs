//! Running the backend's commands. Every external call of the mod goes through [`Exec`], so the
//! daemon uses [`SystemExec`] (PATH lookup, timeouts, children killed when abandoned) and the tests
//! substitute a recorder. Nothing here polls: a call runs once, a daemon is started detached and
//! reaped by a task that waits for its exit.

use std::future::Future;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::Stdio;
use std::time::Duration;

/// What a finished command said.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ExecOutput {
    pub ok: bool,
    pub stdout: String,
    pub stderr: String,
}

/// Why a command did not finish. `NotFound` is a binary that is not on PATH (Shōjiki: a reason,
/// not a silent no-op).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExecError {
    NotFound(String),
    Timeout,
    Failed(String),
}

pub type ExecFuture = Pin<Box<dyn Future<Output = Result<ExecOutput, ExecError>> + Send + 'static>>;

pub trait Exec: Send + Sync + 'static {
    /// The executable `program` resolves to, if any.
    fn find(&self, program: &str) -> Option<PathBuf>;
    /// Runs `program args…` and waits for it, at most `timeout`.
    fn run(&self, program: &str, args: Vec<String>, timeout: Duration) -> ExecFuture;
    /// Starts `program args…` without waiting for it to answer (a backend daemon).
    fn spawn(&self, program: &str, args: Vec<String>) -> Result<(), ExecError>;
}

/// The real thing: `PATH` lookup in the given directories, `tokio::process` children.
#[derive(Clone, Debug, Default)]
pub struct SystemExec {
    path: Vec<PathBuf>,
    envs: Vec<(String, String)>,
}

impl SystemExec {
    /// The directories of the daemon's own `PATH`, read once when the mod is linked.
    pub fn from_env() -> Self {
        let path = std::env::var_os("PATH")
            .map(|p| std::env::split_paths(&p).collect())
            .unwrap_or_default();
        Self {
            path,
            envs: Vec::new(),
        }
    }

    /// Only these directories, extra environment for every child (the tests' fake backends).
    pub fn with(path: Vec<PathBuf>, envs: Vec<(String, String)>) -> Self {
        Self { path, envs }
    }
}

fn is_executable(p: &Path) -> bool {
    std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

impl Exec for SystemExec {
    fn find(&self, program: &str) -> Option<PathBuf> {
        if program.contains('/') {
            let p = PathBuf::from(program);
            return is_executable(&p).then_some(p);
        }
        self.path
            .iter()
            .map(|dir| dir.join(program))
            .find(|p| is_executable(p))
    }

    fn run(&self, program: &str, args: Vec<String>, timeout: Duration) -> ExecFuture {
        let bin = self.find(program);
        let envs = self.envs.clone();
        let name = program.to_string();
        Box::pin(async move {
            let bin = bin.ok_or(ExecError::NotFound(name))?;
            let child = tokio::process::Command::new(bin)
                .args(&args)
                .envs(envs)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                // A timed-out call is abandoned: its child must not outlive the wait.
                .kill_on_drop(true)
                .spawn()
                .map_err(|e| ExecError::Failed(e.to_string()))?;
            match tokio::time::timeout(timeout, child.wait_with_output()).await {
                Ok(Ok(out)) => Ok(ExecOutput {
                    ok: out.status.success(),
                    stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
                    stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
                }),
                Ok(Err(e)) => Err(ExecError::Failed(e.to_string())),
                Err(_) => Err(ExecError::Timeout),
            }
        })
    }

    fn spawn(&self, program: &str, args: Vec<String>) -> Result<(), ExecError> {
        let bin = self
            .find(program)
            .ok_or_else(|| ExecError::NotFound(program.to_string()))?;
        let mut child = tokio::process::Command::new(bin)
            .args(&args)
            .envs(self.envs.clone())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| ExecError::Failed(e.to_string()))?;
        // The daemon outlives the mod on purpose (it keeps the last image on screen). The waiter
        // only reaps it when it exits; it does not poll.
        tokio::spawn(async move {
            let _ = child.wait().await;
        });
        Ok(())
    }
}
