//! The desk saved with a project (docs/ux/sessions.md "The desk with it"): the focused output's active workspace and its
//! windows — app id, title, column and place in it, size, floating rect, the program's command line and folder — and the
//! other mods' parts (the terminal's tabs, the web dock's pages), which the shell hands in. Restoring moves and sizes what
//! is open and launches what is missing; it never closes a window.
//!
//! The compositor part is a trait: [`Niri`] talks to niri's IPC directly, a stand-in until the compositor adapter
//! (`kurashi-compositor`) carries window places and the placing actions (CONTRACT-CHANGE 812).

use std::collections::BTreeSet;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SavedWindow {
    pub app_id: String,
    #[serde(default)]
    pub title: String,
    /// `/proc/<pid>/cmdline` when it was saved: how a missing window is launched again.
    #[serde(default)]
    pub command: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    /// 1-based column and place in it; `None` floating.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub column: Option<(usize, usize)>,
    pub width: i32,
    pub height: i32,
    #[serde(default)]
    pub floating: bool,
    /// A floating window's place in the workspace view.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at: Option<(f64, f64)>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Desk {
    pub saved: u64,
    /// The workspace's name, when it has one: restore goes back there if it still exists.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    pub windows: Vec<SavedWindow>,
    /// The terminal mod's tabs (their folders), handed in by the shell.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub terminal: Vec<String>,
    /// The web dock's pin that was shown, handed in by the shell.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub webdock: Option<String>,
}

/// A window as the compositor has it now.
#[derive(Debug, Clone, PartialEq)]
pub struct Live {
    pub id: u64,
    pub app_id: String,
    pub title: String,
    pub workspace: Option<u64>,
    pub pid: Option<i32>,
    pub column: Option<(usize, usize)>,
    pub size: (i32, i32),
    pub floating: bool,
    pub at: Option<(f64, f64)>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Space {
    pub id: u64,
    pub name: Option<String>,
    pub output: Option<String>,
    pub focused: bool,
}

/// One placing step.
#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    Move {
        id: u64,
        workspace: u64,
    },
    Float {
        id: u64,
    },
    Tile {
        id: u64,
    },
    Width {
        id: u64,
        px: i32,
    },
    Height {
        id: u64,
        px: i32,
    },
    Place {
        id: u64,
        x: f64,
        y: f64,
    },
    /// Focus the window and move its column to `index` (1-based) on its workspace.
    Column {
        id: u64,
        index: usize,
    },
}

/// The compositor as the desk needs it.
pub trait Desktop: Send + Sync {
    fn list(&self) -> Result<(Vec<Space>, Vec<Live>), String>;
    fn act(&self, step: &Step) -> Result<(), String>;
}

/// The desk from what is on screen now: the focused workspace's windows, the tiled ones in column order first.
pub fn capture(
    spaces: &[Space],
    windows: &[Live],
    proc_info: &dyn Fn(i32) -> (Vec<String>, Option<String>),
    now: u64,
) -> Result<Desk, &'static str> {
    let ws = spaces
        .iter()
        .find(|s| s.focused)
        .ok_or("sessions.desk.no_workspace")?;
    let mut list: Vec<SavedWindow> = windows
        .iter()
        .filter(|w| w.workspace == Some(ws.id))
        .map(|w| {
            let (command, cwd) = w.pid.map(proc_info).unwrap_or_default();
            SavedWindow {
                app_id: w.app_id.clone(),
                title: w.title.clone(),
                command,
                cwd,
                column: if w.floating { None } else { w.column },
                width: w.size.0,
                height: w.size.1,
                floating: w.floating,
                at: if w.floating { w.at } else { None },
            }
        })
        .collect();
    list.sort_by_key(|w| (w.floating, w.column.unwrap_or((usize::MAX, 0))));
    Ok(Desk {
        saved: now,
        workspace: ws.name.clone(),
        output: ws.output.clone(),
        windows: list,
        terminal: Vec::new(),
        webdock: None,
    })
}

/// The workspace a restore goes to: the saved name when it still exists, else the focused one.
pub fn target(desk: &Desk, spaces: &[Space]) -> Option<u64> {
    desk.workspace
        .as_ref()
        .and_then(|n| spaces.iter().find(|s| s.name.as_ref() == Some(n)))
        .or_else(|| spaces.iter().find(|s| s.focused))
        .map(|s| s.id)
}

/// Which open window each saved one takes: the same app id, unclaimed; the same title first, then one already on the
/// target workspace, then any. `None`: missing (to launch).
pub fn assign(desk: &Desk, live: &[Live], workspace: u64) -> Vec<Option<u64>> {
    let mut claimed: BTreeSet<u64> = BTreeSet::new();
    desk.windows
        .iter()
        .map(|s| {
            let pick = live
                .iter()
                .filter(|w| w.app_id == s.app_id && !claimed.contains(&w.id))
                .min_by_key(|w| (w.title != s.title, w.workspace != Some(workspace), w.id))
                .map(|w| w.id);
            if let Some(id) = pick {
                claimed.insert(id);
            }
            pick
        })
        .collect()
}

/// The steps that put window `id` where `saved` stood on `workspace`.
pub fn steps(saved: &SavedWindow, id: u64, now_floating: bool, workspace: u64) -> Vec<Step> {
    let mut v = vec![Step::Move { id, workspace }];
    if saved.floating {
        if !now_floating {
            v.push(Step::Float { id });
        }
        v.push(Step::Width {
            id,
            px: saved.width,
        });
        v.push(Step::Height {
            id,
            px: saved.height,
        });
        if let Some((x, y)) = saved.at {
            v.push(Step::Place { id, x, y });
        }
    } else {
        if now_floating {
            v.push(Step::Tile { id });
        }
        v.push(Step::Width {
            id,
            px: saved.width,
        });
        if let Some((col, _)) = saved.column {
            v.push(Step::Column { id, index: col });
        }
    }
    v
}

/// What a restore did, for the document and the report.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Restored {
    pub placed: usize,
    pub launched: usize,
    /// App ids that were launched and did not map in time, or could not be launched.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub failed: Vec<String>,
}

/// Restore `desk`: place what is open, launch what is missing (and wait for it, `wait` at most each), never close
/// anything. Blocking: run it off the runtime.
pub fn restore(
    desk: &Desk,
    d: &dyn Desktop,
    launch: &dyn Fn(&SavedWindow) -> Result<(), String>,
    wait: Duration,
) -> Result<Restored, String> {
    let (spaces, live) = d.list()?;
    let ws = target(desk, &spaces).ok_or("sessions.desk.no_workspace")?;
    let mut ids = assign(desk, &live, ws);
    let mut out = Restored::default();
    let mut known: BTreeSet<u64> = live.iter().map(|w| w.id).collect();
    for (i, s) in desk.windows.iter().enumerate() {
        if ids[i].is_some() {
            continue;
        }
        if s.command.is_empty() || launch(s).is_err() {
            out.failed.push(s.app_id.clone());
            continue;
        }
        out.launched += 1;
        // (polled only while a launched window is awaited: the brief's budget)
        let until = Instant::now() + wait;
        let mut found = None;
        while Instant::now() < until && found.is_none() {
            std::thread::sleep(Duration::from_millis(250));
            if let Ok((_, now)) = d.list() {
                found = now
                    .iter()
                    .find(|w| w.app_id == s.app_id && !known.contains(&w.id))
                    .map(|w| w.id);
            }
        }
        match found {
            Some(id) => {
                known.insert(id);
                ids[i] = Some(id);
            }
            None => out.failed.push(s.app_id.clone()),
        }
    }
    let (_, live) = d.list()?;
    // Tiled windows left to right, so each column index lands where it stood; then the floating ones.
    for (i, s) in desk.windows.iter().enumerate() {
        let Some(id) = ids[i] else { continue };
        let floating = live.iter().find(|w| w.id == id).is_some_and(|w| w.floating);
        for step in steps(s, id, floating, ws) {
            d.act(&step)?;
        }
        out.placed += 1;
    }
    Ok(out)
}

/// The command line and folder of a process (`/proc`).
pub fn proc_info(pid: i32) -> (Vec<String>, Option<String>) {
    let cmd = std::fs::read(format!("/proc/{pid}/cmdline"))
        .map(|b| {
            b.split(|c| *c == 0)
                .filter(|s| !s.is_empty())
                .map(|s| String::from_utf8_lossy(s).into_owned())
                .collect()
        })
        .unwrap_or_default();
    let cwd = std::fs::read_link(format!("/proc/{pid}/cwd"))
        .ok()
        .map(|p| p.to_string_lossy().into_owned());
    (cmd, cwd)
}

/// niri over its socket (`$NIRI_SOCKET`): one request connection per call.
pub struct Niri {
    pub socket: PathBuf,
}

impl Niri {
    /// `None` when the daemon does not run on niri.
    pub fn from_env() -> Option<Self> {
        let s = std::env::var_os("NIRI_SOCKET").filter(|s| !s.is_empty())?;
        Some(Self { socket: s.into() })
    }

    fn send(&self, r: niri_ipc::Request) -> Result<niri_ipc::Response, String> {
        let mut s =
            niri_ipc::socket::Socket::connect_to(&self.socket).map_err(|e| e.to_string())?;
        s.send(r).map_err(|e| e.to_string())?
    }

    fn action(&self, a: niri_ipc::Action) -> Result<(), String> {
        match self.send(niri_ipc::Request::Action(a))? {
            niri_ipc::Response::Handled => Ok(()),
            other => Err(format!("unexpected reply {other:?}")),
        }
    }
}

impl Desktop for Niri {
    fn list(&self) -> Result<(Vec<Space>, Vec<Live>), String> {
        use niri_ipc::{Request, Response};
        let spaces = match self.send(Request::Workspaces)? {
            Response::Workspaces(l) => l
                .into_iter()
                .map(|w| Space {
                    id: w.id,
                    name: w.name,
                    output: w.output,
                    focused: w.is_focused,
                })
                .collect(),
            other => return Err(format!("unexpected reply {other:?}")),
        };
        let windows = match self.send(Request::Windows)? {
            Response::Windows(l) => l
                .into_iter()
                .map(|w| Live {
                    id: w.id,
                    app_id: w.app_id.unwrap_or_default(),
                    title: w.title.unwrap_or_default(),
                    workspace: w.workspace_id,
                    pid: w.pid,
                    column: w.layout.pos_in_scrolling_layout,
                    size: w.layout.window_size,
                    floating: w.is_floating,
                    at: w.layout.tile_pos_in_workspace_view,
                })
                .collect(),
            other => return Err(format!("unexpected reply {other:?}")),
        };
        Ok((spaces, windows))
    }

    fn act(&self, step: &Step) -> Result<(), String> {
        use niri_ipc::{Action, PositionChange, SizeChange, WorkspaceReferenceArg};
        match *step {
            Step::Move { id, workspace } => self.action(Action::MoveWindowToWorkspace {
                window_id: Some(id),
                reference: WorkspaceReferenceArg::Id(workspace),
                focus: false,
            }),
            Step::Float { id } => self.action(Action::MoveWindowToFloating { id: Some(id) }),
            Step::Tile { id } => self.action(Action::MoveWindowToTiling { id: Some(id) }),
            Step::Width { id, px } => self.action(Action::SetWindowWidth {
                id: Some(id),
                change: SizeChange::SetFixed(px),
            }),
            Step::Height { id, px } => self.action(Action::SetWindowHeight {
                id: Some(id),
                change: SizeChange::SetFixed(px),
            }),
            Step::Place { id, x, y } => self.action(Action::MoveFloatingWindow {
                id: Some(id),
                x: PositionChange::SetFixed(x),
                y: PositionChange::SetFixed(y),
            }),
            Step::Column { id, index } => {
                self.action(Action::FocusWindow { id })?;
                self.action(Action::MoveColumnToIndex { index })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    fn live(id: u64, app: &str, title: &str, ws: u64, col: Option<usize>) -> Live {
        Live {
            id,
            app_id: app.into(),
            title: title.into(),
            workspace: Some(ws),
            pid: Some(id as i32),
            column: col.map(|c| (c, 1)),
            size: (800, 600),
            floating: col.is_none(),
            at: col.is_none().then_some((100.0, 50.0)),
        }
    }

    fn spaces() -> Vec<Space> {
        vec![
            Space {
                id: 1,
                name: None,
                output: Some("O".into()),
                focused: true,
            },
            Space {
                id: 2,
                name: Some("code".into()),
                output: Some("O".into()),
                focused: false,
            },
        ]
    }

    #[test]
    fn capture_takes_the_focused_workspace_in_column_order() {
        let w = vec![
            live(5, "kitty", "b", 1, Some(2)),
            live(6, "firefox", "docs", 1, Some(1)),
            live(7, "pavucontrol", "vol", 1, None),
            live(8, "other", "x", 2, Some(1)),
        ];
        let d = capture(
            &spaces(),
            &w,
            &|pid| (vec![format!("app{pid}")], Some("/p".into())),
            9,
        )
        .unwrap();
        let apps: Vec<&str> = d.windows.iter().map(|w| w.app_id.as_str()).collect();
        assert_eq!(apps, ["firefox", "kitty", "pavucontrol"]);
        assert_eq!(d.windows[0].command, ["app6"]);
        assert_eq!(d.windows[2].at, Some((100.0, 50.0)));
        assert!(d.windows[2].floating && d.windows[2].column.is_none());
        assert_eq!(d.output.as_deref(), Some("O"));
    }

    #[test]
    fn assignment_prefers_title_then_workspace_and_claims_once() {
        let d = capture(
            &spaces(),
            &[
                live(1, "kitty", "logs", 1, Some(1)),
                live(2, "kitty", "code", 1, Some(2)),
            ],
            &|_| (vec!["kitty".into()], None),
            0,
        )
        .unwrap();
        let now = vec![
            live(10, "kitty", "code", 2, Some(1)),
            live(11, "kitty", "zsh", 1, Some(1)),
        ];
        // logs → no title match: the one on the target workspace (11); code → 10.
        assert_eq!(assign(&d, &now, 1), [Some(11), Some(10)]);
        assert_eq!(assign(&d, &now[..1], 1), [Some(10), None]);
    }

    #[test]
    fn a_named_workspace_is_the_target_while_it_exists() {
        let mut d = capture(&spaces(), &[], &|_| (vec![], None), 0).unwrap();
        d.workspace = Some("code".into());
        assert_eq!(target(&d, &spaces()), Some(2));
        d.workspace = Some("gone".into());
        assert_eq!(target(&d, &spaces()), Some(1));
    }

    struct Fake {
        state: Mutex<(Vec<Space>, Vec<Live>)>,
        log: Mutex<Vec<Step>>,
    }
    impl Desktop for Fake {
        fn list(&self) -> Result<(Vec<Space>, Vec<Live>), String> {
            Ok(self.state.lock().unwrap().clone())
        }
        fn act(&self, step: &Step) -> Result<(), String> {
            self.log.lock().unwrap().push(step.clone());
            Ok(())
        }
    }

    #[test]
    fn restore_places_the_open_launches_the_missing_and_closes_nothing() {
        let d = capture(
            &spaces(),
            &[
                live(1, "kitty", "code", 1, Some(1)),
                live(2, "firefox", "docs", 1, Some(2)),
                live(3, "pavucontrol", "vol", 1, None),
            ],
            &|pid| (vec![format!("app{pid}")], None),
            0,
        )
        .unwrap();
        let fake = Fake {
            state: Mutex::new((
                spaces(),
                vec![
                    live(20, "kitty", "code", 2, Some(3)),
                    live(30, "pavucontrol", "vol", 2, Some(1)),
                ],
            )),
            log: Mutex::new(vec![]),
        };
        let launched = Mutex::new(vec![]);
        let r = restore(
            &d,
            &fake,
            &|s| {
                launched.lock().unwrap().push(s.command.clone());
                // the app maps its window
                fake.state
                    .lock()
                    .unwrap()
                    .1
                    .push(live(40, &s.app_id, "docs", 1, Some(2)));
                Ok(())
            },
            Duration::from_secs(2),
        )
        .unwrap();
        assert_eq!(
            launched.lock().unwrap().as_slice(),
            [vec!["app2".to_string()]]
        );
        assert_eq!(
            r,
            Restored {
                placed: 3,
                launched: 1,
                failed: vec![]
            }
        );
        let log = fake.log.lock().unwrap();
        assert_eq!(
            log[..3],
            [
                Step::Move {
                    id: 20,
                    workspace: 1
                },
                Step::Width { id: 20, px: 800 },
                Step::Column { id: 20, index: 1 },
            ]
        );
        // the tiled pavucontrol goes back to floating, at its place
        assert!(log.contains(&Step::Float { id: 30 }));
        assert!(log.contains(&Step::Place {
            id: 30,
            x: 100.0,
            y: 50.0
        }));
    }

    #[test]
    fn a_launch_that_never_maps_is_said() {
        let d = capture(
            &spaces(),
            &[live(1, "kitty", "code", 1, Some(1))],
            &|_| (vec!["kitty".into()], None),
            0,
        )
        .unwrap();
        let fake = Fake {
            state: Mutex::new((spaces(), vec![])),
            log: Mutex::new(vec![]),
        };
        let r = restore(&d, &fake, &|_| Ok(()), Duration::from_millis(300)).unwrap();
        assert_eq!(r.failed, ["kitty"]);
        assert_eq!(r.placed, 0);
    }
}
