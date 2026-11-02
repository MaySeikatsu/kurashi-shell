//! A motion profile resolved into the theme's `motion.*` tokens (K83, brief §3 precedence, contract "Tokens").
//!
//! Precedence: built-in default < the style's pack < the user's profile < the user's per-axis keys < reduce motion.
//! Packs layer by block (pack.rs): a profile without `[timing]`, `[form]` or `[accents]` moves the style's. Reduce motion
//! (`reduced`) is whole: no style underneath, no per-axis key over it.
//!
//! The tokens before K83 (`motion.kind`, `motion.style`, `motion.steps`, `motion.timed.*`, `motion.spring.*`,
//! `motion.easing.*`, `motion.<duration>_ms`) are derived from the result exactly as `kurashi-theme/tokens.rs` derived
//! them from a profile and a look's `[decor] motion.*` (the code moved here); they stay until every surface reads the
//! new families.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde_json::{Value, json};

use crate::curve::{self, Curve, Spec};
use crate::forms::{self, FormMeta, SURFACES};
use crate::pack::{Accents, Base, Forms, Pack, ROLES, Registry, Role};
use crate::recipe::{self, Recipe};

/// The user's per-axis keys (`theme.motion.*`) as the config holds them: `""`, `0`, `-1` and `profile` are "the
/// profile's".
#[derive(Clone, Debug, PartialEq)]
pub struct Axes {
    /// `theme.motion.timing.{open,close,fast,effects}`.
    pub timing: [String; 4],
    /// `theme.motion.timing.*_ms`.
    pub timing_ms: [u32; 4],
    /// `theme.motion.form.{open,close}`.
    pub form: (String, String),
    /// `theme.motion.form.<surface>.{open,close}`, the island's included.
    pub surfaces: BTreeMap<String, (String, String)>,
    /// `theme.motion.form.island.follow`.
    pub island_follow: bool,
    pub content: String,
    pub stagger_ms: i64,
    pub squash: f64,
    pub jelly: f64,
    pub shadow: String,
}

impl Default for Axes {
    fn default() -> Self {
        Axes {
            timing: Default::default(),
            timing_ms: [0; 4],
            form: Default::default(),
            surfaces: BTreeMap::new(),
            island_follow: true,
            content: "profile".into(),
            stagger_ms: -1,
            squash: -1.0,
            jelly: -1.0,
            shadow: "profile".into(),
        }
    }
}

/// What the theme resolves motion from.
#[derive(Clone, Debug, PartialEq)]
pub struct Request {
    /// `theme.motion.profile` in effect (reduce motion forces `reduced`).
    pub profile: String,
    /// The profile the style (or the look in effect) recommends — its `theme:` layer value; `""` for none. Its blocks
    /// show under a profile that has none of its own.
    pub style_profile: String,
    pub axes: Axes,
    /// `a11y.reduce_motion`: `reduced`, whatever the profile says, with no per-axis key over it.
    pub reduce_motion: bool,
    /// Where the user's packs are (kurashid: [`crate::pack::user_dir`]); none = the built-ins only.
    pub user_dirs: Vec<PathBuf>,
}

impl Default for Request {
    fn default() -> Self {
        Request {
            profile: "expressive".into(),
            style_profile: String::new(),
            axes: Axes::default(),
            reduce_motion: false,
            user_dirs: vec![],
        }
    }
}

impl Request {
    /// A request for one profile alone.
    pub fn profile(id: &str) -> Request {
        Request {
            profile: id.into(),
            ..Request::default()
        }
    }
}

/// The resolved tokens (flat dotted keys, as the theme document's) and what did not apply, for the theme's notes.
#[derive(Clone, Debug, Default)]
pub struct Output {
    pub tokens: BTreeMap<String, Value>,
    pub notes: Vec<String>,
}

/// K74's four timed roles (Caelestia's M3 expressive tokens): the default when nothing names a curve or a duration.
const K74: [(&str, f64); 4] = [
    ("expressive", 500.0),
    ("emphasized", 400.0),
    ("expressive-fast", 350.0),
    ("effects", 200.0),
];
/// The small controls' durations (name, base ms before speed and profile).
const DURATIONS: [(&str, f64); 5] = [
    ("instant", 0.0),
    ("quick", 120.0),
    ("standard", 220.0),
    ("emphasized", 320.0),
    ("long", 500.0),
];
/// Reduce motion's ceiling for any duration (K83 D1).
pub const REDUCED_MS: i64 = 150;

/// Resolve with the built-in packs and the request's user directories.
pub fn resolve(req: &Request, speed: f64, chrome: &str) -> Output {
    let reg = Registry::load(&req.user_dirs);
    resolve_in(req, &reg, speed, chrome)
}

/// Resolve against a given registry. `speed` is `theme.motion.speed`; `chrome` the chrome in effect (lively keycaps
/// bounce more, K42).
pub fn resolve_in(req: &Request, reg: &Registry, speed: f64, chrome: &str) -> Output {
    let mut notes: Vec<String> = reg.diags.iter().map(|d| format!("motion: {d}")).collect();
    // W59.7: every pack's recipes, a form each once valid; the rest say why they are skipped.
    let (recipes, shadowed) = recipe::collect(reg);
    for r in recipes.iter().chain(&shadowed) {
        notes.extend(r.diags.iter().map(|d| recipe::note(r, d)));
    }
    let wanted = if req.reduce_motion {
        "reduced"
    } else if req.profile.is_empty() {
        "expressive"
    } else {
        req.profile.as_str()
    };
    // A missing pack falls back to the style's, then to expressive (brief §10).
    let top = reg
        .find(wanted)
        .or_else(|| {
            notes.push(format!(
                "motion: profile {wanted} not found (config.diag.motion.missing)"
            ));
            reg.find(&req.style_profile)
        })
        .or_else(|| reg.find("expressive"))
        .expect("the expressive pack is built in");
    // Under the a11y force the base is reduce motion's whatever a user's `reduced.toml` says: its fades stay capped and
    // no vestibular or flashing form gets through.
    let base = if req.reduce_motion {
        Base::Reduced
    } else {
        top.base.unwrap_or(Base::Expressive)
    };
    // Reduce motion is whole: no style's blocks underneath, no user's keys over it.
    let pure = base == Base::Reduced;
    let style = (!pure && req.style_profile != top.id)
        .then(|| reg.find(&req.style_profile))
        .flatten();
    let timing = top
        .timing
        .as_ref()
        .or(style.and_then(|s| s.timing.as_ref()));
    let form_pack = if top.forms.is_some() {
        Some(top)
    } else {
        style
    };
    let forms_block = form_pack.and_then(|p| p.forms.as_ref());
    let accents = top
        .accents
        .as_ref()
        .or(style.and_then(|s| s.accents.as_ref()));
    let user = (!pure).then_some(&req.axes);
    let r = Resolver {
        reg,
        top,
        style,
        base,
        pure,
        timing,
        forms: forms_block,
        accents,
        user,
        recipes: &recipes,
        sk: speed.clamp(0.25, 4.0),
        speed,
        chrome,
    };
    let mut out = Output::default();
    r.write(&mut out.tokens, &mut notes);
    let mut seen = std::collections::BTreeSet::new();
    notes.retain(|n| seen.insert(n.clone()));
    out.notes = notes;
    out
}

struct Resolver<'a> {
    reg: &'a Registry,
    top: &'a Pack,
    style: Option<&'a Pack>,
    base: Base,
    pure: bool,
    timing: Option<&'a [Role; 4]>,
    forms: Option<&'a Forms>,
    accents: Option<&'a Accents>,
    user: Option<&'a Axes>,
    recipes: &'a [Recipe],
    sk: f64,
    speed: f64,
    chrome: &'a str,
}

/// A duration after speed and profile (tokens.rs `duration_ms`, K74; reduce motion caps it).
fn duration_ms(base_ms: f64, profile: Base, speed: f64) -> i64 {
    let speed = speed.clamp(0.25, 4.0);
    let profile_k = match profile {
        Base::None => return 0,
        Base::Calm | Base::Expressive | Base::Reduced => 1.0,
        Base::Lively => 0.8,
    };
    let ms = (base_ms * profile_k / speed).round() as i64;
    if profile == Base::Reduced {
        ms.min(REDUCED_MS)
    } else {
        ms
    }
}

/// Cubic-bezier control points per easing role (tokens.rs `easing`).
fn easing(profile: Base) -> [(&'static str, [f64; 4]); 4] {
    match profile {
        Base::None => {
            ["enter", "exit", "emphasized", "continuous"].map(|n| (n, [0.0, 0.0, 1.0, 1.0]))
        }
        // Caelestia's (M3 expressive) default spatial curve on arrival, its accelerating exit.
        Base::Expressive => [
            ("enter", [0.38, 1.21, 0.22, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.05, 0.7, 0.1, 1.0]),
            ("continuous", [0.2, 0.0, 0.0, 1.0]),
        ],
        Base::Calm => [
            ("enter", [0.05, 0.7, 0.1, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.2, 0.0, 0.0, 1.0]),
            ("continuous", [0.4, 0.0, 0.2, 1.0]),
        ],
        // Slight overshoot on arrival; exits stay crisp.
        Base::Lively => [
            ("enter", [0.34, 1.4, 0.64, 1.0]),
            ("exit", [0.3, 0.0, 0.8, 0.15]),
            ("emphasized", [0.3, 1.2, 0.3, 1.0]),
            ("continuous", [0.4, 0.0, 0.2, 1.0]),
        ],
        // Reduce motion: every control fades on the effects curve (never overshoots).
        Base::Reduced => {
            ["enter", "exit", "emphasized", "continuous"].map(|n| (n, [0.34, 0.8, 0.34, 1.0]))
        }
    }
}

/// A staircase as a QML `bezierCurve` (W53.0a, the `stepped` form): `n` equal steps, each taken at once and then held,
/// in straight segments — a surface moves in visible jumps (16-bit menus) whatever the frame rate.
pub fn stepped_curve(n: usize) -> Vec<f64> {
    let n = n.clamp(1, 60);
    let r = |v: f64| (v * 1e4).round() / 1e4;
    let mut c = Vec::with_capacity(n * 12);
    for k in 0..n {
        let (x0, x1) = (k as f64 / n as f64, (k + 1) as f64 / n as f64);
        let (y0, y1) = (x0, x1);
        let xj = x0 + (x1 - x0).min(0.002) / 2.0;
        // The jump (x0, y0) → (xj, y1), then the hold (xj, y1) → (x1, y1); straight lines: c1 = start, c2 = end.
        c.extend([x0, y0, xj, y1, xj, y1].map(r));
        c.extend([xj, y1, x1, y1, x1, y1].map(r));
    }
    c
}

impl Resolver<'_> {
    /// A curve value resolved: presets and written curves directly, a named one from the packs.
    fn curve_of(&self, spec: &Spec, notes: &mut Vec<String>) -> Option<Curve> {
        spec.curve().or_else(|| {
            let Spec::Named(name) = spec else { return None };
            let c = self.reg.curve(name, &[Some(self.top), self.style]);
            if c.is_none() {
                notes.push(format!(
                    "motion: curve {name} not found (config.diag.motion.curve)"
                ));
            }
            c
        })
    }

    /// The user's curve for a role, if they set one that resolves.
    fn user_curve(&self, i: usize, notes: &mut Vec<String>) -> Option<Curve> {
        let s = self.user?.timing[i].trim();
        if s.is_empty() {
            return None;
        }
        match curve::parse(s) {
            Ok(spec) => self.curve_of(&spec, notes),
            Err(e) => {
                notes.push(format!("motion: timing.{} {s:?}: {}", ROLES[i], e.key()));
                None
            }
        }
    }

    /// The pack's curve for a role (the profile's `[timing]`, else the style's).
    fn pack_curve(&self, i: usize, notes: &mut Vec<String>) -> Option<Curve> {
        let spec = self.timing?[i].curve.as_ref()?;
        self.curve_of(spec, notes)
    }

    /// A role's duration before speed as the profile alone has it: the pack's, else K74's.
    fn pack_role_ms(&self, i: usize) -> f64 {
        match self.timing.map_or(0, |t| t[i].ms) {
            p if p > 0 => f64::from(p),
            _ => K74[i].1,
        }
    }

    /// A role's duration before speed: the user's, the pack's, else K74's.
    fn role_ms(&self, i: usize) -> f64 {
        let user = self.user.map_or(0, |u| u.timing_ms[i]);
        let pack = self.timing.map_or(0, |t| t[i].ms);
        match (user, pack) {
            (u, _) if u > 0 => f64::from(u),
            (_, p) if p > 0 => f64::from(p),
            _ => K74[i].1,
        }
    }

    /// Whether `id` may run on `surface` now (and, under reduce motion, moves nothing and flashes nothing): its id.
    fn usable(&self, id: &str, surface: &str, notes: &mut Vec<String>) -> Option<String> {
        if let Some(m) = forms::form(id) {
            return self.usable_form(m, surface, notes).map(|m| m.id.to_owned());
        }
        // A recipe (W59.7) serves every surface; a skipped one falls back (its reasons are in the notes already), and
        // reduce motion never runs one that turns or zooms a lot.
        if let Some(r) = self.recipes.iter().find(|r| r.id == id) {
            if !r.ok() {
                notes.push(format!(
                    "motion: form {id} is a recipe that is skipped (config.diag.recipe)"
                ));
                return None;
            }
            return (!(self.pure && r.vestibular())).then(|| r.id.clone());
        }
        notes.push(format!(
            "motion: form {id} unknown (config.diag.form.unknown)"
        ));
        None
    }

    fn usable_form(
        &self,
        m: &'static FormMeta,
        surface: &str,
        notes: &mut Vec<String>,
    ) -> Option<&'static FormMeta> {
        let id = m.id;
        if !m.available {
            notes.push(format!(
                "motion: form {id} not available yet ({})",
                forms::REASON_UNAVAILABLE
            ));
            return None;
        }
        if !m.serves(surface) {
            notes.push(format!(
                "motion: form {id} cannot serve {surface} ({})",
                forms::REASON_SURFACE
            ));
            return None;
        }
        if self.pure && (m.vestibular() || m.flash()) {
            return None;
        }
        Some(m)
    }

    /// The form of a surface class for one direction: the user's for the class, the user's default, the pack's for the
    /// class, the pack's default — the first that may run there. The island follows the defaults unless the user turns
    /// `form.island.follow` off (D3).
    fn form(&self, surface: &str, open: bool, notes: &mut Vec<String>) -> String {
        if self.base == Base::None {
            return "none".into();
        }
        self.chain(surface, open, notes)
    }

    /// [`Resolver::form`] as if motion were on (today's tokens keep the look's form under `none`).
    fn chain(&self, surface: &str, open: bool, notes: &mut Vec<String>) -> String {
        fn pick<'s>(open: bool, pair: (Option<&'s str>, Option<&'s str>)) -> Option<&'s str> {
            if open { pair.0 } else { pair.1 }
        }
        let own_class = surface != "island" || self.user.is_some_and(|u| !u.island_follow);
        let mut chain: Vec<Option<&str>> = vec![];
        if let Some(u) = self.user {
            if own_class && let Some((o, c)) = u.surfaces.get(surface) {
                chain.push(pick(open, (Some(o.as_str()), Some(c.as_str()))));
            }
            chain.push(pick(
                open,
                (Some(u.form.0.as_str()), Some(u.form.1.as_str())),
            ));
        }
        if let Some(f) = self.forms {
            if own_class && let Some((o, c)) = f.surfaces.get(surface) {
                chain.push(pick(open, (o.as_deref(), c.as_deref())));
            }
            chain.push(pick(open, (f.open.as_deref(), f.close.as_deref())));
        }
        chain
            .into_iter()
            .flatten()
            .filter(|id| !id.is_empty())
            .find_map(|id| self.usable(id, surface, notes))
            .unwrap_or_else(|| if self.pure { "fade" } else { "grow" }.into())
    }

    /// The form today's tokens name (`motion.style`, Entrance): the default opening form, one of the forms before K83.
    fn legacy_style(&self, notes: &mut Vec<String>) -> &'static str {
        // Under `none` the look's form still shaped the (unused) timed curves: a stepped look kept its staircase.
        let form = self.chain("panel", true, notes);
        forms::LEGACY
            .into_iter()
            .find(|l| *l == form)
            .unwrap_or("grow")
    }

    fn accent_num(&self, user: impl Fn(&Axes) -> f64, pack: Option<f64>, default: f64) -> f64 {
        if matches!(self.base, Base::None | Base::Reduced) {
            return 0.0;
        }
        match self.user.map(user) {
            Some(v) if v >= 0.0 => v,
            _ => pack.unwrap_or(default),
        }
    }

    fn write(&self, t: &mut BTreeMap<String, Value>, notes: &mut Vec<String>) {
        let base = self.base;
        let speed = self.speed;
        for (n, b) in DURATIONS {
            t.insert(format!("motion.{n}_ms"), json!(duration_ms(b, base, speed)));
        }
        for (n, b) in easing(base) {
            t.insert(format!("motion.easing.{n}"), json!(b));
        }
        t.insert("motion.profile".into(), json!(self.top.id));

        // K74 / W53.0a (moved from tokens.rs): how surfaces move — `timed` on curves, `spring` on K42's springs, `none`
        // cuts, `stepped` quantises every timed curve into jumps held `motion.steps` frames at 60 Hz. The profile `none`
        // still wins: no curves, no steps.
        let style = self.legacy_style(notes);
        let stepped = style == "stepped";
        t.insert(
            "motion.kind".into(),
            json!(match base {
                Base::None => "none",
                _ if stepped => "stepped",
                Base::Expressive | Base::Reduced => "timed",
                _ => "spring",
            }),
        );
        t.insert(
            "motion.style".into(),
            json!(if base == Base::None { "none" } else { style }),
        );
        let hold = self
            .forms
            .and_then(|f| f.params.get("stepped"))
            .and_then(|p| p.get("hold"))
            .and_then(Value::as_f64)
            .unwrap_or(4.0)
            .max(1.0);
        t.insert("motion.steps".into(), json!(hold as i64));
        // A rubber-band form overshoots on arrival unless the profile names its own curves.
        let rubber = curve::preset("rubber").expect("built in").curve();
        let springs = matches!(base, Base::Calm | Base::Lively);
        let (spring, damping) = match base {
            Base::None | Base::Reduced => (0.0, 1.0),
            // (Expressive: what is not moved on its curves yet springs as calm does.)
            Base::Calm | Base::Expressive => (4.0, 0.45),
            Base::Lively => (3.2, 0.26),
        };
        let spring_k = (spring * self.sk * 100.0).round() / 100.0;
        for (i, n) in ROLES.into_iter().enumerate() {
            let dur = duration_ms(self.role_ms(i), base, speed);
            t.insert(format!("motion.timed.{n}_ms"), json!(dur));
            let user = self.user_curve(i, notes);
            let own_pack = self.pack_curve(i, notes);
            let own = user
                .as_ref()
                .and_then(Curve::cubic_points)
                .or_else(|| own_pack.as_ref().and_then(Curve::cubic_points));
            let k74 = curve::preset(K74[i].0).expect("built in").curve();
            let steps_n = ((dur as f64) / (hold * 1000.0 / 60.0)).round() as usize;
            let timed = if stepped {
                stepped_curve(steps_n)
            } else if let Some(c) = own {
                c
            } else if style == "rubber" && n != "close" && n != "effects" {
                rubber.cubic_points().expect("cubic")
            } else {
                k74.cubic_points().expect("cubic")
            };
            t.insert(format!("motion.timed.{n}_curve"), json!(timed));

            // The new token: what the role runs on now; and what the profile alone would run on (Settings: "the profile
            // would use …", rule 1 — Settings cannot resolve packs itself), the same without the user's curve and ms.
            let user_ms = self.user.is_some_and(|u| u.timing_ms[i] > 0);
            let pack_ms = self.timing.is_some_and(|t| t[i].ms > 0);
            let pdur = duration_ms(self.pack_role_ms(i), base, speed);
            let p_steps = ((pdur as f64) / (hold * 1000.0 / 60.0)).round() as usize;
            let p_timed = own_pack
                .as_ref()
                .and_then(Curve::cubic_points)
                .unwrap_or_else(|| {
                    if style == "rubber" && n != "close" && n != "effects" {
                        rubber.cubic_points().expect("cubic")
                    } else {
                        k74.cubic_points().expect("cubic")
                    }
                });
            let (token, profile) = if base == Base::None {
                (json!({"kind": "none"}), json!({"kind": "none"}))
            } else {
                let profile = if stepped {
                    json!({"kind": "steps", "ms": pdur, "n": p_steps.clamp(1, 60)})
                } else if springs && n != "effects" {
                    json!({"kind": "spring_q", "ms": 0, "spring": spring_k, "damping": damping})
                } else if let Some(c) = &own_pack {
                    self.curve_token(c, pdur, pack_ms)
                } else {
                    json!({"kind": "cubic", "ms": pdur, "points": p_timed})
                };
                let token = if let Some(c) = &user {
                    self.curve_token(c, dur, user_ms)
                } else if stepped {
                    json!({"kind": "steps", "ms": dur, "n": steps_n.clamp(1, 60)})
                } else if springs && n != "effects" {
                    json!({"kind": "spring_q", "ms": 0, "spring": spring_k, "damping": damping})
                } else if let Some(c) = &own_pack {
                    self.curve_token(c, dur, user_ms || pack_ms)
                } else {
                    json!({"kind": "cubic", "ms": dur, "points": timed})
                };
                (token, profile)
            };
            t.insert(format!("motion.curve.{n}"), token);
            t.insert(format!("motion.profile_curve.{n}"), profile);
        }

        // Springs (K42): overshoot of arrivals (QML Easing.OutBack amplitude) and a spring for retargetable morphs (QML
        // SpringAnimation `spring`/`damping`). Calm settles without a bounce, keycap chrome bounces more, `none` and
        // reduce motion have no spring at all (`motion.spring.on` false).
        let overshoot = match (base, self.chrome) {
            (Base::None | Base::Reduced, _) => 0.0,
            (Base::Calm | Base::Expressive, _) => 0.6,
            (Base::Lively, "flat") => 1.4,
            (Base::Lively, "keycap") => 2.2,
            (Base::Lively, "soft") => 1.0,
            (Base::Lively, _) => 0.4,
        };
        t.insert("motion.spring.overshoot".into(), json!(overshoot));
        t.insert(
            "motion.spring.on".into(),
            json!(!matches!(base, Base::None | Base::Reduced)),
        );
        t.insert("motion.spring.spring".into(), json!(spring_k));
        t.insert("motion.spring.damping".into(), json!(damping));
        // W34 (rows 360, 363): squash and stretch mid-morph and the neck's wobble on landing — lively's by default.
        let a = self.accents;
        let squash = self.accent_num(
            |u| u.squash,
            a.and_then(|a| a.squash),
            if base == Base::Lively { 0.06 } else { 0.0 },
        );
        t.insert("motion.spring.squash".into(), json!(squash));

        // Forms per surface class and direction, and the parameters of those in use.
        let mut used: Vec<String> = vec![];
        for surface in SURFACES {
            for (dir, open) in [("open", true), ("close", false)] {
                let f = self.form(surface, open, notes);
                t.insert(format!("motion.form.{surface}.{dir}"), json!(f));
                if !used.contains(&f) {
                    used.push(f);
                }
            }
        }
        if let Some(fb) = self.forms {
            for f in used {
                if let Some(p) = fb.params.get(&f) {
                    t.insert(format!("motion.form_params.{f}"), Value::Object(p.clone()));
                }
            }
        }
        // The forms meta: every built-in form, then every valid recipe (W59.7, `recipe: true`); and each recipe the packs
        // define as `motion.recipe.<id>` — the tracks to run, or why it is skipped (Settings lists both).
        let mut meta = forms::meta();
        if let Value::Object(m) = &mut meta {
            for r in self.recipes.iter().filter(|r| r.ok()) {
                m.insert(r.id.clone(), r.meta());
            }
        }
        t.insert("motion.forms".into(), meta);
        for r in self.recipes {
            t.insert(format!("motion.recipe.{}", r.id), r.token());
        }

        // Accents.
        let still = matches!(base, Base::None | Base::Reduced);
        t.insert("motion.accent.squash".into(), json!(squash));
        t.insert(
            "motion.accent.jelly".into(),
            json!(self.accent_num(|u| u.jelly, a.and_then(|a| a.jelly), 0.0)),
        );
        t.insert(
            "motion.accent.overshoot_cap".into(),
            json!(if still {
                0.0
            } else {
                a.and_then(|a| a.overshoot_cap).unwrap_or(1.0)
            }),
        );
        let stagger = match self.user.map(|u| u.stagger_ms) {
            _ if still => 0,
            Some(v) if v >= 0 => v,
            _ => a.and_then(|a| a.stagger_ms).unwrap_or(0),
        };
        t.insert("motion.accent.stagger_ms".into(), json!(stagger));
        let word = |user: Option<&str>, pack: Option<&String>, default: &str| -> String {
            match user {
                Some(u) if u != "profile" && !u.is_empty() => u.to_owned(),
                _ => pack.cloned().unwrap_or_else(|| default.to_owned()),
            }
        };
        let content = match base {
            Base::None | Base::Reduced => "with".to_owned(),
            _ => word(
                self.user.map(|u| u.content.as_str()),
                a.and_then(|a| a.content.as_ref()),
                "late",
            ),
        };
        t.insert("motion.accent.content".into(), json!(content));
        let shadow = match base {
            Base::Reduced => "fade".to_owned(),
            _ => word(
                self.user.map(|u| u.shadow.as_str()),
                a.and_then(|a| a.shadow.as_ref()),
                "carry",
            ),
        };
        t.insert("motion.accent.shadow".into(), json!(shadow));
    }

    /// A written curve as its `motion.curve.<role>` token; `dur` is the role's duration after speed and `explicit`
    /// whether that duration was set for this curve (the user's own for any curve; the pack's for the pack's own curve):
    /// a spring takes it as its response, else keeps its own (a pack's duration does not reshape the user's spring).
    fn curve_token(&self, c: &Curve, dur: i64, explicit: bool) -> Value {
        match c {
            Curve::Cubic(_) | Curve::Linear => {
                json!({"kind": "cubic", "ms": dur, "points": c.cubic_points()})
            }
            Curve::Spring {
                response_ms,
                bounce,
            } => {
                let ms = if explicit {
                    dur
                } else {
                    duration_ms(*response_ms, self.base, self.speed)
                };
                json!({"kind": "spring", "ms": ms, "response": ms, "bounce": bounce})
            }
            Curve::SpringQ { spring, damping } => json!({
                "kind": "spring_q",
                "ms": 0,
                "spring": (spring * self.sk * 100.0).round() / 100.0,
                "damping": damping,
            }),
            Curve::Steps(n) => json!({"kind": "steps", "ms": dur, "n": n}),
            Curve::None => json!({"kind": "none"}),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn res(req: &Request) -> BTreeMap<String, Value> {
        resolve_in(req, Registry::bundled(), 1.0, "flat").tokens
    }

    #[test]
    fn todays_profiles_resolve_as_before() {
        let e = res(&Request::profile("expressive"));
        assert_eq!(e["motion.kind"], "timed");
        assert_eq!(e["motion.style"], "grow");
        assert_eq!(e["motion.timed.open_ms"], 500);
        assert_eq!(
            e["motion.timed.open_curve"],
            json!([0.38, 1.21, 0.22, 1.0, 1.0, 1.0])
        );
        assert_eq!(
            e["motion.curve.open"],
            json!({"kind": "cubic", "ms": 500, "points": [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]})
        );
        assert_eq!(e["motion.form.panel.open"], "grow");
        let c = res(&Request::profile("calm"));
        assert_eq!(c["motion.kind"], "spring");
        assert_eq!(
            c["motion.curve.open"],
            json!({"kind": "spring_q", "ms": 0, "spring": 4.0, "damping": 0.45})
        );
        assert_eq!(c["motion.curve.effects"]["kind"], "cubic");
        let l = res(&Request::profile("lively"));
        assert_eq!(l["motion.standard_ms"], 176);
        assert_eq!(l["motion.spring.squash"], 0.06);
        assert_eq!(l["motion.accent.squash"], 0.06);
        assert_eq!(l["motion.spring.overshoot"], 1.4);
        let n = res(&Request::profile("none"));
        assert_eq!(n["motion.kind"], "none");
        assert_eq!(n["motion.standard_ms"], 0);
        assert_eq!(n["motion.curve.open"], json!({"kind": "none"}));
        assert_eq!(n["motion.form.island.close"], "none");
        assert_eq!(n["motion.spring.on"], false);
    }

    #[test]
    fn a_timing_profile_moves_the_styles_forms_and_curves() {
        // Calm on washi is what it was before K83: washi's bleed and curves on calm's springs.
        let req = Request {
            profile: "calm".into(),
            style_profile: "washi".into(),
            ..Request::default()
        };
        let t = res(&req);
        assert_eq!(t["motion.profile"], "calm");
        assert_eq!(t["motion.style"], "bleed");
        assert_eq!(t["motion.kind"], "spring");
        assert_eq!(t["motion.timed.open_ms"], 360);
        assert_eq!(
            t["motion.timed.open_curve"],
            json!([0.2, 0.0, 0.1, 1.0, 1.0, 1.0])
        );
        // A full pack replaces the style's.
        let req = Request {
            profile: "fluent".into(),
            style_profile: "washi".into(),
            ..Request::default()
        };
        let t = res(&req);
        assert_eq!(t["motion.style"], "slide");
        assert_eq!(t["motion.timed.effects_ms"], 83);
    }

    /// A user's spring keeps its own response on a pack that sets the role's duration (washi: open 360 ms); the pack's
    /// duration shapes only the pack's own curves, and the user's own duration still wins over the spring's.
    #[test]
    fn a_users_spring_keeps_its_response_over_the_packs_duration() {
        let mut req = Request::profile("washi");
        req.axes.timing[0] = "spring(550ms, 0.45)".into();
        let t = res(&req);
        assert_eq!(
            t["motion.curve.open"],
            json!({"kind": "spring", "ms": 550, "response": 550, "bounce": 0.45})
        );
        req.axes.timing_ms[0] = 300;
        let t = res(&req);
        assert_eq!(t["motion.curve.open"]["response"], 300);
        // What washi alone would run on, for Settings: its own curve at its own 360 ms, whatever the user set.
        assert_eq!(t["motion.profile_curve.open"]["kind"], "cubic");
        assert_eq!(t["motion.profile_curve.open"]["ms"], 360);
    }

    #[test]
    fn user_axes_override_the_profile() {
        let mut req = Request::profile("expressive");
        req.axes.timing[0] = "spring(400ms, 0.3)".into();
        req.axes.timing_ms[1] = 250;
        req.axes.form.0 = "slide".into();
        req.axes
            .surfaces
            .insert("toast".into(), ("zoom".into(), "".into()));
        req.axes.jelly = 0.5;
        req.axes.content = "cascade".into();
        let t = res(&req);
        assert_eq!(
            t["motion.curve.open"],
            json!({"kind": "spring", "ms": 400, "response": 400, "bounce": 0.3})
        );
        assert_eq!(t["motion.timed.close_ms"], 250);
        assert_eq!(t["motion.curve.close"]["ms"], 250);
        assert_eq!(t["motion.form.panel.open"], "slide");
        assert_eq!(t["motion.form.panel.close"], "grow");
        assert_eq!(t["motion.form.toast.open"], "zoom");
        assert_eq!(t["motion.form.toast.close"], "grow");
        assert_eq!(t["motion.style"], "slide");
        assert_eq!(t["motion.accent.jelly"], 0.5);
        assert_eq!(t["motion.accent.content"], "cascade");
    }

    #[test]
    fn the_island_follows_the_default_unless_told_not_to() {
        let mut req = Request::profile("expressive");
        req.axes.form = ("zoom".into(), "fade".into());
        req.axes
            .surfaces
            .insert("island".into(), ("slide".into(), "".into()));
        let t = res(&req);
        assert_eq!(t["motion.form.island.open"], "zoom", "follows");
        req.axes.island_follow = false;
        let t = res(&req);
        assert_eq!(t["motion.form.island.open"], "slide");
        assert_eq!(t["motion.form.island.close"], "fade");
    }

    #[test]
    fn forms_that_cannot_run_fall_back_with_a_note() {
        // (every form is available since W59.9a: a surface the form cannot serve takes the same path)
        let mut req = Request::profile("fluent");
        req.axes.form.0 = "liquid".into();
        let out = resolve_in(&req, Registry::bundled(), 1.0, "flat");
        assert_eq!(out.tokens["motion.form.panel.open"], "liquid");
        assert_eq!(out.tokens["motion.form.sidebar.open"], "slide");
        assert!(
            out.notes.iter().any(|n| n.contains(forms::REASON_SURFACE)),
            "{:?}",
            out.notes
        );
        // The origami draft: its paper forms have landed (W59.4); the toast falls as a drop (W59.5).
        let t = res(&Request::profile("origami"));
        assert_eq!(t["motion.form.panel.open"], "fold");
        assert_eq!(t["motion.form.sidebar.open"], "roll");
        assert_eq!(t["motion.form.toast.close"], "crumple");
        assert_eq!(t["motion.form.toast.open"], "drop");
        assert_eq!(t["motion.form.peek.open"], "grow");
    }

    #[test]
    fn reduce_motion_is_short_fades_whatever_else_is_set() {
        let mut req = Request {
            profile: "lively".into(),
            style_profile: "kawaii".into(),
            reduce_motion: true,
            ..Request::default()
        };
        req.axes.form = ("grow".into(), "grow".into());
        req.axes.timing[0] = "bouncy".into();
        req.axes.squash = 0.1;
        let t = resolve_in(&req, Registry::bundled(), 0.5, "keycap").tokens;
        assert_eq!(t["motion.profile"], "reduced");
        for s in SURFACES {
            assert_eq!(t[&format!("motion.form.{s}.open")], "fade", "{s}");
            assert_eq!(t[&format!("motion.form.{s}.close")], "fade", "{s}");
        }
        for r in ROLES {
            let c = &t[&format!("motion.curve.{r}")];
            assert_eq!(c["kind"], "cubic");
            assert!(c["ms"].as_i64().unwrap() <= REDUCED_MS && c["ms"].as_i64().unwrap() > 0);
            assert!(t[&format!("motion.timed.{r}_ms")].as_i64().unwrap() <= REDUCED_MS);
        }
        assert_eq!(t["motion.kind"], "timed");
        assert_eq!(t["motion.style"], "fade");
        assert_eq!(t["motion.spring.on"], false);
        assert_eq!(t["motion.spring.squash"], 0.0);
        assert_eq!(t["motion.accent.jelly"], 0.0);
        assert_eq!(t["motion.accent.overshoot_cap"], 0.0);
        assert!(t["motion.standard_ms"].as_i64().unwrap() > 0);
        assert!(t["motion.long_ms"].as_i64().unwrap() <= REDUCED_MS);
    }

    #[test]
    fn stepped_profiles_quantise_into_steps() {
        let t = res(&Request::profile("snes"));
        assert_eq!(t["motion.kind"], "stepped");
        assert_eq!(t["motion.steps"], 1);
        assert_eq!(
            t["motion.curve.open"],
            json!({"kind": "steps", "ms": 67, "n": 4})
        );
        assert_eq!(t["motion.form_params.stepped"], json!({"hold": 1}));
        // Speed changes the number of steps, as before.
        let fast = resolve_in(&Request::profile("snes"), Registry::bundled(), 2.0, "flat").tokens;
        assert_eq!(fast["motion.curve.open"]["n"], 2);
    }

    #[test]
    fn speed_is_in_every_duration() {
        let t = resolve_in(&Request::profile("calm"), Registry::bundled(), 2.0, "flat").tokens;
        assert_eq!(t["motion.curve.open"]["spring"], 8.0);
        assert_eq!(t["motion.curve.effects"]["ms"], 100);
        let mut req = Request::profile("expressive");
        req.axes.timing[0] = "fluid".into();
        let t = resolve_in(&req, Registry::bundled(), 2.0, "flat").tokens;
        assert_eq!(t["motion.curve.open"]["ms"], 250);
    }

    #[test]
    fn a_missing_profile_falls_back_to_the_styles_then_expressive() {
        let req = Request {
            profile: "gone".into(),
            style_profile: "fluent".into(),
            ..Request::default()
        };
        let out = resolve_in(&req, Registry::bundled(), 1.0, "flat");
        assert_eq!(out.tokens["motion.profile"], "fluent");
        assert!(
            out.notes
                .iter()
                .any(|n| n.contains("config.diag.motion.missing"))
        );
        assert_eq!(
            res(&Request::profile("gone"))["motion.profile"],
            "expressive"
        );
    }

    #[test]
    fn a_pack_with_a_bad_curve_falls_back_to_the_default() {
        let mut reg = Registry::bundled().clone();
        let (p, diags) = crate::pack::parse(
            "[timing]\nopen = \"cubic-bezier(2, 0, 0, 1)\"\nopen_ms = 300\nclose = \"nope\"\n[form]\n[accents]\n",
            "odd",
            false,
        )
        .unwrap();
        reg.packs.push(p);
        reg.diags.extend(diags);
        let out = resolve_in(&Request::profile("odd"), &reg, 1.0, "flat");
        assert_eq!(
            out.tokens["motion.timed.open_curve"],
            json!([0.38, 1.21, 0.22, 1.0, 1.0, 1.0]),
            "K74's curve"
        );
        assert_eq!(out.tokens["motion.timed.open_ms"], 300);
        assert_eq!(
            out.tokens["motion.curve.close"]["points"],
            out.tokens["motion.timed.close_curve"]
        );
        assert!(
            out.notes
                .iter()
                .any(|n| n.contains("error.config.curve.x_range")),
            "{:?}",
            out.notes
        );
        assert!(
            out.notes
                .iter()
                .any(|n| n.contains("config.diag.motion.curve")),
            "{:?}",
            out.notes
        );
    }

    #[test]
    fn every_bundled_pack_resolves_on_every_surface() {
        for p in &Registry::bundled().packs {
            let t = res(&Request::profile(&p.id));
            for s in SURFACES {
                for d in ["open", "close"] {
                    let f = t[&format!("motion.form.{s}.{d}")].as_str().unwrap();
                    let m = forms::form(f).unwrap();
                    assert!(m.available && m.serves(s), "{} {s} {d}: {f}", p.id);
                }
            }
            assert!(t["motion.forms"]["fold"].is_object());
        }
    }

    /// W59.7: a user pack's recipes are forms — in the meta, in `motion.recipe.<id>`, pickable on any surface and as the
    /// pack's own forms; a skipped one falls back; reduce motion never runs a vestibular one.
    #[test]
    fn recipes_are_forms() {
        let brief = include_str!("../tests/recipes-brief.toml");
        let dir = std::env::temp_dir().join(format!("kurashi-recipes-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("mine.toml");
        std::fs::write(&file, brief).unwrap();
        std::fs::write(
            dir.join("broken.toml"),
            "[recipes.wobbly]\n[[recipes.wobbly.track]]\nprop = \"wobble\"\nkeys = [[0, 1]]\n",
        )
        .unwrap();
        let reg = Registry::load(std::slice::from_ref(&dir));
        std::fs::remove_dir_all(&dir).unwrap();
        let run = |req: &Request| resolve_in(req, &reg, 1.0, "flat");

        // The pack "mine" as the profile: its forms are its recipes.
        let out = run(&Request::profile("mine"));
        let t = &out.tokens;
        assert_eq!(t["motion.form.panel.open"], "pop-tilt");
        assert_eq!(t["motion.form.panel.close"], "fade");
        assert_eq!(t["motion.form.toast.open"], "drop-squash");
        assert_eq!(t["motion.form.sidebar.close"], "slide-blur");
        assert_eq!(
            t["motion.style"], "grow",
            "today's token names a form before K83"
        );
        assert_eq!(t["motion.forms"]["pop-tilt"]["recipe"], true);
        assert_eq!(
            t["motion.forms"]["pop-tilt"]["flags"],
            json!(["vestibular"])
        );
        assert_eq!(t["motion.forms"]["slide-blur"]["tier"], "layer");
        assert_eq!(
            t["motion.forms"]["pop-tilt"]["surfaces"]
                .as_array()
                .unwrap()
                .len(),
            12
        );
        assert!(
            t["motion.forms"].get("wobbly").is_none(),
            "a skipped recipe is no form"
        );
        let pop = &t["motion.recipe.pop-tilt"];
        assert_eq!(pop["ok"], true);
        assert_eq!(pop["label"], "Pop and tilt");
        assert_eq!(pop["pack"], "mine");
        assert_eq!(pop["path"], json!(file.to_string_lossy()));
        assert_eq!(
            pop["tracks"][0]["keys"],
            json!([[0, 0.6], [0.7, 1.06], [1, 1]])
        );
        let bad = &t["motion.recipe.wobbly"];
        assert_eq!(bad["ok"], false);
        assert_eq!(bad["diags"][0]["key"], "config.diag.recipe.prop");
        assert!(
            out.notes
                .iter()
                .any(|n| n.contains("recipe wobbly (broken)")),
            "{:?}",
            out.notes
        );

        // Picked on one surface under another profile; a skipped one falls back along the chain.
        let mut req = Request::profile("expressive");
        req.axes
            .surfaces
            .insert("toast".into(), ("drop-squash".into(), "wobbly".into()));
        let t = run(&req).tokens;
        assert_eq!(t["motion.form.toast.open"], "drop-squash");
        assert_eq!(t["motion.form.toast.close"], "grow");
        assert_eq!(t["motion.form.panel.open"], "grow");

        // Reduce motion: the `reduced` profile whole; a user's reduced pack naming a vestibular recipe still fades.
        let mut req = Request::profile("mine");
        req.reduce_motion = true;
        let t = run(&req).tokens;
        assert_eq!(t["motion.form.panel.open"], "fade");
        assert_eq!(t["motion.form.toast.open"], "fade");
        let recipes = brief.split_once("[recipes.pop-tilt]").unwrap().1;
        let (p, d) = crate::pack::parse(
            &format!(
                "name = \"reduced\"\nbase = \"reduced\"\n[form]\nopen = \"pop-tilt\"\n\
                 [form.toast]\nopen = \"drop-squash\"\n[recipes.pop-tilt]{recipes}"
            ),
            "reduced",
            false,
        )
        .unwrap();
        assert!(d.is_empty(), "{d:?}");
        let mut reg2 = reg.clone();
        let slot = reg2.packs.iter_mut().find(|p| p.id == "reduced").unwrap();
        *slot = p;
        let t = resolve_in(&req, &reg2, 1.0, "flat").tokens;
        assert_eq!(
            t["motion.form.panel.open"], "fade",
            "pop-tilt zooms from 0.6: vestibular"
        );
        assert_eq!(
            t["motion.form.toast.open"], "drop-squash",
            "within 0.8–1.2, no turn"
        );
    }
}
