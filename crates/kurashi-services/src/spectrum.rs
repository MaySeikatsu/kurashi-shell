//! `svc.audio.spectrum` (K48, W24-media; I111): live audio levels from a supervised `cava`, with Caelestia's command
//! line (`services/Cava.qml`: the config on stdin, `cava -p /dev/stdin`, raw ascii on stdout, one line per frame of
//! `;`-separated values in `0..=ascii_max_range`). 16 bars, 30 frames a second, mono.
//!
//! Refcounted: the daemon starts [`start`] on the first subscriber and drops the handle on the last, which kills cava
//! (`kill_on_drop`). A line equal to the last one is not published; cava's `sleep_timer` stops its output while the
//! audio is silent, so silence is one all-zero document and then no patches (Ma). cava missing or ending by itself is
//! `available: false` with a reason, never an invented level (Shōjiki).

use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::util::{DocSink, Emitter, ServiceHandle};

/// Bars per frame (PROTOCOL `svc.audio.spectrum`).
pub const BARS: usize = 16;
/// Frames a second at most: cava's `framerate`.
pub const FRAMERATE: u32 = 30;
/// The values cava writes go from 0 to this.
pub const RANGE: u32 = 100;
/// Seconds of silence after which cava stops writing.
pub const SLEEP_S: u32 = 3;

/// Reasons of `svc.audio.spectrum.reason`.
pub const REASON_MISSING: &str = "media.spectrum.reason.missing";
pub const REASON_EXITED: &str = "media.spectrum.reason.exited";

/// cava's config (Caelestia's, at 30 frames a second and 16 bars).
pub fn config() -> String {
    format!(
        "[general]\nframerate={FRAMERATE}\nbars={BARS}\nsleep_timer={SLEEP_S}\n\
         [output]\nchannels=mono\nmethod=raw\nraw_target=/dev/stdout\ndata_format=ascii\nascii_max_range={RANGE}\n"
    )
}

/// cava's arguments: the config is read from stdin.
pub fn args() -> [&'static str; 2] {
    ["-p", "/dev/stdin"]
}

/// One line of cava's raw ascii output (`12;0;100;…;`, the trailing `;` optional) as levels in `0..=1`, rounded to
/// hundredths. `None` for anything that is not [`BARS`] numbers: a partial line is dropped, not padded.
pub fn parse_line(line: &str) -> Option<Vec<f64>> {
    let line = line.trim();
    let line = line.strip_suffix(';').unwrap_or(line);
    if line.is_empty() {
        return None;
    }
    let mut out = Vec::with_capacity(BARS);
    for part in line.split(';') {
        let v: u32 = part.trim().parse().ok()?;
        let v = v.min(RANGE);
        out.push(f64::from(v) / f64::from(RANGE));
    }
    (out.len() == BARS).then_some(out)
}

/// The document of a running cava: its bars.
pub fn doc(bars: &[f64]) -> Value {
    json!({"available": true, "bars": bars})
}

/// The document before the first frame: no level is known yet, so every bar is still.
pub fn doc_waiting() -> Value {
    doc(&[0.0; BARS])
}

/// The document without levels: `available` false and why.
pub fn doc_unavailable(reason: &str) -> Value {
    json!({"available": false, "reason": reason, "bars": []})
}

/// The `cava` program on `path` (a `PATH` value), if any.
pub fn which(path: &str) -> Option<PathBuf> {
    path.split(':')
        .filter(|d| !d.is_empty())
        .map(|d| Path::new(d).join("cava"))
        .find(|p| is_executable(p))
}

fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// Runs `program` (cava) while the handle lives and publishes its frames to `sink`. Drop the handle to stop it.
pub fn start(program: Option<PathBuf>, sink: Arc<dyn DocSink>) -> ServiceHandle {
    let em = Emitter::new(sink);
    let Some(program) = program else {
        em.emit(doc_unavailable(REASON_MISSING));
        return ServiceHandle::inert();
    };
    em.emit(doc_waiting());
    let task = tokio::spawn(async move {
        run(&program, &em).await;
        em.emit(doc_unavailable(REASON_EXITED));
    });
    ServiceHandle::new(task)
}

async fn run(program: &Path, em: &Emitter) {
    let spawned = tokio::process::Command::new(program)
        .args(args())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn();
    let mut child = match spawned {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(error = %e, program = %program.display(), "cava did not start");
            return;
        }
    };
    tracing::info!(program = %program.display(), "cava started");
    // The config, then EOF: cava reads `-p /dev/stdin` to the end before it starts.
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(config().as_bytes()).await;
        let _ = stdin.shutdown().await;
    }
    let Some(stdout) = child.stdout.take() else {
        return;
    };
    let mut lines = BufReader::new(stdout).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if let Some(bars) = parse_line(&line) {
            // The emitter drops a frame equal to the last one: a still level costs nothing.
            em.emit(doc(&bars));
        }
    }
    let status = child.wait().await;
    tracing::warn!(?status, "cava ended by itself");
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    #[test]
    fn the_config_is_caelestias_at_30_fps_and_16_bars() {
        let c = config();
        for line in [
            "framerate=30",
            "bars=16",
            "sleep_timer=3",
            "channels=mono",
            "method=raw",
            "raw_target=/dev/stdout",
            "data_format=ascii",
            "ascii_max_range=100",
        ] {
            assert!(c.lines().any(|l| l == line), "{line} in {c}");
        }
        assert_eq!(args(), ["-p", "/dev/stdin"]);
    }

    #[test]
    fn lines_parse_into_sixteen_levels() {
        let line = "0;10;20;30;40;50;60;70;80;90;100;100;50;25;5;0;";
        let bars = parse_line(line).unwrap();
        assert_eq!(bars.len(), BARS);
        assert_eq!(bars[0], 0.0);
        assert_eq!(bars[1], 0.1);
        assert_eq!(bars[10], 1.0);
        assert_eq!(bars[13], 0.25);
        // Without the trailing separator, with spaces and a CR.
        let no_tail = "1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16\r";
        assert_eq!(parse_line(no_tail).unwrap()[15], 0.16);
        // Past the range is the top, never more.
        let over = "250;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;";
        assert_eq!(parse_line(over).unwrap()[0], 1.0);
    }

    #[test]
    fn partial_and_garbled_lines_are_dropped() {
        assert_eq!(parse_line(""), None);
        assert_eq!(parse_line(";"), None);
        assert_eq!(parse_line("1;2;3;"), None, "too few");
        assert_eq!(
            parse_line("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;"),
            None,
            "too many"
        );
        assert_eq!(parse_line("1;2;x;4;5;6;7;8;9;10;11;12;13;14;15;16;"), None);
        assert_eq!(parse_line("-1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;"), None);
    }

    #[test]
    fn documents_have_the_contract_shape() {
        assert_eq!(doc_waiting()["bars"].as_array().unwrap().len(), BARS);
        assert_eq!(doc_waiting()["available"], true);
        let u = doc_unavailable(REASON_MISSING);
        assert_eq!(u["available"], false);
        assert_eq!(u["reason"], REASON_MISSING);
    }

    #[derive(Default)]
    struct Docs(Mutex<Vec<Value>>);
    impl DocSink for Docs {
        fn set(&self, doc: Value) {
            self.0.lock().unwrap().push(doc);
        }
    }

    #[tokio::test]
    async fn no_cava_is_unavailable_with_its_reason() {
        let docs = Arc::new(Docs::default());
        let _h = start(None, docs.clone());
        assert_eq!(
            *docs.0.lock().unwrap(),
            vec![doc_unavailable(REASON_MISSING)]
        );
        assert_eq!(which(""), None);
    }

    /// A fake cava: reads its config from stdin, prints three frames (two equal), then stays silent.
    #[tokio::test]
    async fn a_fake_cava_publishes_changed_frames_only_and_stops_on_drop() {
        let dir = tempfile::tempdir().unwrap();
        let cava = dir.path().join("cava");
        let pidfile = dir.path().join("pid");
        std::fs::write(
            &cava,
            format!(
                "#!/bin/sh\necho $$ > {}\ncat > {}/config\n\
                 echo '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;'\n\
                 echo '50;50;50;50;50;50;50;50;50;50;50;50;50;50;50;50;'\n\
                 echo '50;50;50;50;50;50;50;50;50;50;50;50;50;50;50;50;'\n\
                 echo '1;2;3;'\nexec sleep 30\n",
                pidfile.display(),
                dir.path().display()
            ),
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&cava, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(
            which(&format!("/nonexistent:{}", dir.path().display())),
            Some(cava.clone())
        );

        let docs = Arc::new(Docs::default());
        let h = start(Some(cava), docs.clone());
        for _ in 0..100 {
            if docs.0.lock().unwrap().len() >= 2 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        {
            let got = docs.0.lock().unwrap();
            // The waiting document is all zeros, so the first (silent) frame is not published again.
            assert_eq!(*got, vec![doc_waiting(), doc(&[0.5; BARS])]);
        }
        let config = std::fs::read_to_string(dir.path().join("config")).unwrap();
        assert_eq!(config, super::config(), "the config came on stdin");
        let pid: i32 = std::fs::read_to_string(&pidfile)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        drop(h);
        // kill_on_drop: the process is gone shortly after the last subscriber left.
        let mut gone = false;
        for _ in 0..100 {
            let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
            // A zombie (state Z) is gone too: nothing runs.
            if stat.is_empty() || stat.split_whitespace().nth(2) == Some("Z") {
                gone = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }
        assert!(gone, "cava still runs after the handle was dropped");
    }
}
