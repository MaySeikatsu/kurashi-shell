//! `svc.recorder` (K47): screen recording as a supervised `gpu-screen-recorder` (Noctalia
//! `Services/ScreenRecorderService.qml`: `-w <output> -f 60 -a default_output -o <file>`, stopped with SIGINT so it
//! finishes the file) or `wf-recorder` (`-o <output> -f <file> [--audio]`). Pure: which program, its arguments, the
//! file's name and the folder. The daemon runs the process only while recording.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    GpuScreenRecorder,
    WfRecorder,
}

impl Backend {
    pub fn program(self) -> &'static str {
        match self {
            Backend::GpuScreenRecorder => "gpu-screen-recorder",
            Backend::WfRecorder => "wf-recorder",
        }
    }

    /// The program's arguments. Without an output, gpu-screen-recorder takes every screen (`screen`) and wf-recorder
    /// the only one.
    pub fn args(self, output: Option<&str>, file: &Path, audio: bool) -> Vec<String> {
        let file = file.to_string_lossy().into_owned();
        match self {
            Backend::GpuScreenRecorder => {
                let mut a = vec![
                    "-w".into(),
                    output.unwrap_or("screen").into(),
                    "-f".into(),
                    "60".into(),
                ];
                if audio {
                    a.extend(["-a".into(), "default_output".into()]);
                }
                a.extend(["-o".into(), file]);
                a
            }
            Backend::WfRecorder => {
                let mut a = Vec::new();
                if let Some(o) = output {
                    a.extend(["-o".into(), o.into()]);
                }
                // -y: never stop to ask about an existing file (the name is new anyway).
                a.extend(["-y".into(), "-f".into(), file]);
                if audio {
                    a.push("--audio".into());
                }
                a
            }
        }
    }
}

/// The first executable `program` on `path` (a `$PATH` value).
pub fn which(program: &str, path: &str) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    path.split(':').filter(|d| !d.is_empty()).find_map(|d| {
        let p = Path::new(d).join(program);
        let meta = std::fs::metadata(&p).ok()?;
        (meta.is_file() && meta.permissions().mode() & 0o111 != 0).then_some(p)
    })
}

/// The backend for the `recorder.backend` setting (`auto`, `gpu_screen_recorder`, `wf_recorder`), if its program is
/// installed. Automatic takes the first one found, gpu-screen-recorder first.
pub fn pick(setting: &str, path: &str) -> Option<Backend> {
    let order: &[Backend] = match setting {
        "gpu_screen_recorder" => &[Backend::GpuScreenRecorder],
        "wf_recorder" => &[Backend::WfRecorder],
        _ => &[Backend::GpuScreenRecorder, Backend::WfRecorder],
    };
    order
        .iter()
        .copied()
        .find(|b| which(b.program(), path).is_some())
}

/// `kurashi-2026-10-21_10-00-00.mp4` from a `YYYY-MM-DD_HH-MM-SS` stamp.
pub fn file_name(stamp: &str) -> String {
    format!("kurashi-{stamp}.mp4")
}

/// The Videos folder: `XDG_VIDEOS_DIR` from `user-dirs.dirs` under `config_home`, else `~/Videos`.
pub fn videos_dir(home: &Path, config_home: &Path) -> PathBuf {
    std::fs::read_to_string(config_home.join("user-dirs.dirs"))
        .ok()
        .and_then(|text| {
            text.lines().find_map(|l| {
                let v = l.trim().strip_prefix("XDG_VIDEOS_DIR=")?;
                let v = v.trim().trim_matches('"');
                let v = v.replace("$HOME", &home.to_string_lossy());
                (!v.is_empty()).then(|| PathBuf::from(v))
            })
        })
        .unwrap_or_else(|| home.join("Videos"))
}

/// Reasons of `svc.recorder.reason`.
pub const REASON_MISSING: &str = "power.recorder.reason.missing";
pub const REASON_FAILED: &str = "power.recorder.reason.failed";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_are_noctalias_and_wf_recorders() {
        let f = Path::new("/v/kurashi-x.mp4");
        assert_eq!(
            Backend::GpuScreenRecorder
                .args(Some("DP-1"), f, true)
                .join(" "),
            "-w DP-1 -f 60 -a default_output -o /v/kurashi-x.mp4"
        );
        assert_eq!(
            Backend::GpuScreenRecorder.args(None, f, false).join(" "),
            "-w screen -f 60 -o /v/kurashi-x.mp4"
        );
        assert_eq!(
            Backend::WfRecorder.args(Some("DP-1"), f, true).join(" "),
            "-o DP-1 -y -f /v/kurashi-x.mp4 --audio"
        );
    }

    #[test]
    fn pick_follows_the_setting_and_what_is_installed() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let wf = dir.path().join("wf-recorder");
        std::fs::write(&wf, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&wf, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.path().to_string_lossy().into_owned();
        assert_eq!(pick("auto", &path), Some(Backend::WfRecorder));
        assert_eq!(pick("gpu_screen_recorder", &path), None);
        assert_eq!(pick("wf_recorder", &path), Some(Backend::WfRecorder));
        assert_eq!(pick("auto", ""), None);
    }

    #[test]
    fn videos_dir_reads_user_dirs() {
        let dir = tempfile::tempdir().unwrap();
        let home = Path::new("/home/u");
        assert_eq!(
            videos_dir(home, dir.path()),
            PathBuf::from("/home/u/Videos")
        );
        std::fs::write(
            dir.path().join("user-dirs.dirs"),
            "XDG_VIDEOS_DIR=\"$HOME/Filme\"\n",
        )
        .unwrap();
        assert_eq!(videos_dir(home, dir.path()), PathBuf::from("/home/u/Filme"));
        assert_eq!(
            file_name("2026-10-21_10-00-00"),
            "kurashi-2026-10-21_10-00-00.mp4"
        );
    }
}
