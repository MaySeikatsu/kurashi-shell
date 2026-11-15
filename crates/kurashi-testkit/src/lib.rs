//! Dev-only test helpers shared by the test suites (CLAUDE.md rule 10): a private `dbus-daemon` bus and
//! scratch directories. Nothing here touches the user's session or system bus, and no shipped crate depends
//! on this one.
//!
//! The suites run the real `dbus-daemon` from `nix develop`, so names, signals and disconnects behave as on
//! the session bus.

use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Child, Command, Stdio};

/// The `<policy>` body the suites use: any client may send and eavesdrop, and may own names.
pub const DEFAULT_POLICY: &str =
    r#"<allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/>"#;

/// A temporary directory, removed on drop. Its name starts with `kurashi-<tag>-`, so a leftover is traceable.
pub struct Scratch(tempfile::TempDir);

impl Scratch {
    pub fn new(tag: &str) -> Self {
        let dir = tempfile::Builder::new()
            .prefix(&format!("kurashi-{tag}-"))
            .tempdir()
            .unwrap();
        Self(dir)
    }

    pub fn path(&self) -> &Path {
        self.0.path()
    }

    /// The address of a bus listening on this directory's `bus` socket (see [`TestBus::start_in`]).
    pub fn bus_addr(&self) -> String {
        format!("unix:path={}", self.path().join("bus").display())
    }
}

/// A private session-type `dbus-daemon`. Dropping it, or calling [`TestBus::kill`], kills only this child:
/// every connection on the bus sees its socket close.
pub struct TestBus {
    child: Option<Child>,
    addr: String,
    /// The directory a [`TestBus::start`] bus made for itself. A [`TestBus::start_in`] bus leaves its
    /// scratch to the caller, who may restart a bus there.
    _own_dir: Option<Scratch>,
}

impl TestBus {
    /// A bus on a socket in a directory of its own (`unix:tmpdir=`); the daemon picks the address.
    pub fn start() -> Self {
        Self::start_with_policy(DEFAULT_POLICY)
    }

    /// As [`TestBus::start`], with `policy` as the `<policy>` body instead of [`DEFAULT_POLICY`].
    pub fn start_with_policy(policy: &str) -> Self {
        let dir = Scratch::new("bus");
        let conf = dir.path().join("bus.conf");
        write_conf(
            &conf,
            &format!("unix:tmpdir={}", dir.path().display()),
            policy,
        );
        let (child, printed) = spawn(&conf);
        Self {
            child: Some(child),
            addr: printed,
            _own_dir: Some(dir),
        }
    }

    /// A bus on `scratch`'s `bus` socket (`unix:path=`). The address is known before the daemon runs, so a
    /// bus started again at the same address is reached by the same clients. A socket a killed daemon left
    /// behind is removed first.
    pub fn start_in(scratch: &Scratch) -> Self {
        let socket = scratch.path().join("bus");
        let _ = std::fs::remove_file(&socket);
        let conf = scratch.path().join("bus.conf");
        write_conf(
            &conf,
            &format!("unix:path={}", socket.display()),
            DEFAULT_POLICY,
        );
        let (child, printed) = spawn(&conf);
        // The printed address carries a `,guid=` suffix; the socket path is what must match.
        assert!(
            printed.starts_with(&scratch.bus_addr()),
            "the daemon listens where the test expects: {printed}"
        );
        Self {
            child: Some(child),
            addr: printed,
            _own_dir: None,
        }
    }

    pub fn addr(&self) -> &str {
        &self.addr
    }

    pub async fn conn(&self) -> zbus::Connection {
        zbus::connection::Builder::address(self.addr.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }

    /// A connection that also owns `name`, for serving fake objects.
    pub async fn server(&self, name: &str) -> zbus::Connection {
        let c = self.conn().await;
        c.request_name(name.to_owned()).await.unwrap();
        c
    }

    /// Kills the daemon and waits for it. Calling it twice, or dropping after it, does nothing more.
    pub fn kill(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for TestBus {
    fn drop(&mut self) {
        self.kill();
    }
}

/// Writes the bus config. `listen` is the address the daemon listens on, as `unix:…`.
fn write_conf(path: &Path, listen: &str, policy: &str) {
    std::fs::write(
        path,
        format!(
            r#"<busconfig><type>session</type>
<listen>{listen}</listen><auth>EXTERNAL</auth>
<policy context="default">{policy}</policy>
</busconfig>"#
        ),
    )
    .unwrap();
}

/// Starts the daemon and returns it with the address it printed, once it accepts clients.
fn spawn(conf: &Path) -> (Child, String) {
    let mut child = Command::new("dbus-daemon")
        .arg(format!("--config-file={}", conf.display()))
        .args(["--nofork", "--print-address"])
        .stdout(Stdio::piped())
        .spawn()
        .expect("dbus-daemon (run inside nix develop)");
    let mut printed = String::new();
    BufReader::new(child.stdout.as_mut().unwrap())
        .read_line(&mut printed)
        .unwrap();
    (child, printed.trim().to_owned())
}
