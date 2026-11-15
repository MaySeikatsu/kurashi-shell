//! `kurashi mod …` (K154): the mod tools that need no daemon — the ruleset's check, the extension points, and what a
//! mod's views reach (for writing its `uses`). They read folders, so they run in a checkout and in CI alike.

use std::path::PathBuf;

use clap::Subcommand;
use kurashi_mods::{check, points};

#[derive(Subcommand, Clone)]
pub enum ModCmd {
    /// Hold mods to the ruleset (docs/MODS.md "Feeling native"): each PATH is a mod's folder; exit 1 when one fails
    Check {
        paths: Vec<PathBuf>,
        /// Every mod under DIR (default: ./mods)
        #[arg(long, num_args = 0..=1, default_missing_value = "mods")]
        all: Option<PathBuf>,
        /// Count the notes as failures too
        #[arg(long)]
        strict: bool,
    },
    /// The shell's extension points (`--markdown`: docs/MODS.md's table)
    Points {
        #[arg(long)]
        markdown: bool,
    },
    /// What a mod's views read and call beyond its own: lines for its `uses`
    Reach { path: PathBuf },
    /// Write a new mod from the templates (it passes `mod check` as written): `kurashi mod new tea --name Tea --icon
    /// emoji_food_beverage --with widget,panel,menu`
    New {
        /// Its id and folder name: lowercase letters, digits and `-`
        id: String,
        /// The name people see (default: the id)
        #[arg(long)]
        name: Option<String>,
        /// A Material Symbols name
        #[arg(long, default_value = "extension")]
        icon: String,
        #[arg(long, default_value = "")]
        description: String,
        /// What it ships, comma-separated: widget, peek, panel, desk, tile, menu, settings
        #[arg(long, value_delimiter = ',', default_value = "widget,panel,menu")]
        with: Vec<String>,
        /// What it reads and calls beyond its own, comma-separated (`doc:svc.clock,action:island.expand?`)
        #[arg(long, value_delimiter = ',')]
        uses: Vec<String>,
        /// Where its folder goes (default: your mods, $XDG_DATA_HOME/kurashi/mods; `mods` in a checkout)
        #[arg(long)]
        dir: Option<PathBuf>,
    },
}

pub struct Out {
    pub text: String,
    pub code: i32,
}

pub fn run(cmd: ModCmd, json: bool) -> Out {
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).expect("crate version");
    match cmd {
        ModCmd::Check { paths, all, strict } => {
            let mut dirs = paths;
            if let Some(root) = all {
                dirs.extend(kurashi_mods::mod_dirs(&root));
            }
            if dirs.is_empty() {
                return Out {
                    text:
                        "kurashi mod check: no mod named (a folder with a mod.toml, or --all [DIR])"
                            .into(),
                    code: 2,
                };
            }
            let reports: Vec<check::Report> =
                dirs.iter().map(|d| check::check_dir(d, &version)).collect();
            let failed = reports
                .iter()
                .filter(|r| !r.passed() || (strict && r.count(check::Level::Warn) > 0))
                .count();
            let text = if json {
                serde_json::to_string_pretty(&reports).expect("reports serialize")
            } else {
                let mut t: String = reports.iter().map(check::Report::text).collect();
                t.push_str(&format!(
                    "{} mod(s) checked, {} failed",
                    reports.len(),
                    failed
                ));
                t
            };
            Out {
                text,
                code: i32::from(failed > 0),
            }
        }
        ModCmd::Points { markdown } => Out {
            text: if json {
                serde_json::to_string_pretty(points::POINTS).expect("points serialize")
            } else if markdown {
                points::markdown()
            } else {
                points::POINTS
                    .iter()
                    .map(|p| format!("{:<32} {:<36} {}", p.id, p.fill, p.about))
                    .collect::<Vec<_>>()
                    .join("\n")
            },
            code: 0,
        },
        ModCmd::New {
            id,
            name,
            icon,
            description,
            with,
            uses,
            dir,
        } => {
            let spec = kurashi_mods::scaffold::Spec {
                name: name.unwrap_or_else(|| id.clone()),
                description: if description.is_empty() {
                    format!("{id}: say in one line what it is for")
                } else {
                    description
                },
                id,
                icon,
                with,
                uses,
            };
            let root = dir.unwrap_or_else(|| {
                std::env::var_os("XDG_DATA_HOME")
                    .map(PathBuf::from)
                    .or_else(|| {
                        std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share"))
                    })
                    .unwrap_or_default()
                    .join("kurashi/mods")
            });
            match spec.write(&root) {
                Ok(path) => {
                    let report = check::check_dir(&path, &version);
                    Out {
                        text: if json {
                            serde_json::json!({"path": path, "check": report}).to_string()
                        } else {
                            format!(
                                "wrote {}\n{}next: restart the shell's daemon, then turn it on in Settings › Mods (or `kurashi act mod.enable '{{\"id\":\"{}\"}}'`)",
                                path.display(),
                                report.text(),
                                spec.id
                            )
                        },
                        code: i32::from(!report.passed()),
                    }
                }
                Err(e) => Out {
                    text: format!("kurashi mod new: {e}"),
                    code: 2,
                },
            }
        }
        ModCmd::Reach { path } => {
            let id = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_owned();
            let r = check::reach(&path);
            let mut uses: Vec<String> = Vec::new();
            let none = kurashi_mods::Contract::default();
            for (d, _) in &r.docs {
                let u = format!("doc:{d}");
                if !none.may_read(&id, d) && !uses.contains(&u) {
                    uses.push(u);
                }
            }
            for (a, _) in &r.actions {
                let u = format!("action:{a}");
                if !none.may_call(&id, a) && !uses.contains(&u) {
                    uses.push(u);
                }
            }
            for (k, _) in &r.intents {
                let u = format!("intent:{k}");
                if !none.may_send(&id, k) && !uses.contains(&u) {
                    uses.push(u);
                }
            }
            uses.sort();
            Out {
                text: if json {
                    serde_json::to_string(&uses).expect("uses serialize")
                } else {
                    format!(
                        "uses = [{}]",
                        uses.iter()
                            .map(|u| format!("\"{u}\""))
                            .collect::<Vec<_>>()
                            .join(", ")
                    )
                },
                code: 0,
            }
        }
    }
}
