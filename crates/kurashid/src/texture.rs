//! K59: the material texture and its light as theme tokens (`texture.*`, `light.*`, DESIGN-SYSTEM "Texture and
//! light"), the tile cache, the daytime sun, and the wallpaper bake behind the wallpaper mod's picture filter.
//!
//! Tiles are generated once per parameters on a blocking thread; until one is ready the tokens say "no texture" and the
//! theme is republished when it arrives (no flash, no blocked runtime). The light is resolved here except the pointer:
//! a lamp at the pointer is a view concern (only the frontend sees the pointer, over its own surfaces).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use kurashi_texture::{Beam, CrackStyle, InkRole, Kind, Params, Shading, Tile};
use serde_json::{Map, Value, json};

use crate::config::ConfigStore;
use crate::theme::{b, f, s};

/// The shade amplitude at strength 1, before the legibility cap.
const AMP_FULL: f64 = 0.18;
/// Body text against the relief's darkest and lightest point.
const TEXT_CONTRAST: f64 = 4.5;

/// The largest output scale × 100 (the tile's device pixels per logical pixel).
static SCALE: AtomicU32 = AtomicU32::new(100);
/// Republishes the theme (set by `theme::register`): a tile became ready, the outputs' scale changed.
static AGAIN: OnceLock<Arc<dyn Fn() + Send + Sync>> = OnceLock::new();

enum Slot {
    Pending,
    Ready(PathBuf, Arc<Tile>),
}

fn cache() -> &'static Mutex<HashMap<String, Slot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Slot>>> = OnceLock::new();
    CACHE.get_or_init(Default::default)
}

pub fn on_ready(again: Arc<dyn Fn() + Send + Sync>) {
    let _ = AGAIN.set(again);
}

fn again() {
    if let Some(f) = AGAIN.get() {
        f();
    }
}

/// The compositor's outputs changed: a larger scale needs a sharper tile.
pub fn set_outputs(outputs: &[kurashi_compositor::Output]) {
    let max = outputs.iter().map(|o| o.scale).fold(1.0f64, f64::max);
    let k = ((max * 4.0).ceil() * 25.0) as u32;
    if SCALE.swap(k, Ordering::Relaxed) != k {
        again();
    }
}

fn device_scale() -> f32 {
    SCALE.load(Ordering::Relaxed) as f32 / 100.0
}

static CACHE_DIR: OnceLock<PathBuf> = OnceLock::new();

/// Tiles and bakes live here: `$XDG_CACHE_HOME/kurashi/texture` (tests set their own, once per process).
pub fn cache_dir() -> PathBuf {
    CACHE_DIR
        .get()
        .cloned()
        .unwrap_or_else(|| crate::xdg_dir("cache").join("texture"))
}

/// For tests: keep tiles and bakes out of the user's cache.
pub fn set_cache_dir(dir: PathBuf) {
    let _ = CACHE_DIR.set(dir);
}

fn key(p: &Params) -> String {
    format!(
        "{}:{:.2}:{:.2}:{}:{}:{:.2}",
        p.kind.name(),
        p.wrinkles,
        p.cracks,
        p.crack_style.name(),
        p.tint,
        p.device_scale
    )
}

/// The tile for `p`: ready, or `None` while it is generated on a blocking thread (the theme is republished when it is
/// done). Outside a runtime (tests) it is generated in place.
pub fn tile(p: &Params) -> Option<(PathBuf, Arc<Tile>)> {
    let k = key(p);
    {
        let mut c = cache().lock().expect("texture cache");
        match c.get(&k) {
            Some(Slot::Ready(path, t)) => return Some((path.clone(), t.clone())),
            Some(Slot::Pending) => return None,
            None => {
                c.insert(k.clone(), Slot::Pending);
            }
        }
    }
    let p = *p;
    let make = move || match kurashi_texture::tile_file(&cache_dir(), &p) {
        Ok((path, t)) => {
            cache()
                .lock()
                .expect("texture cache")
                .insert(k, Slot::Ready(path, Arc::new(t)));
            true
        }
        Err(e) => {
            tracing::warn!(error = %e, kind = p.kind.name(), "texture tile failed");
            cache().lock().expect("texture cache").remove(&k);
            false
        }
    };
    match tokio::runtime::Handle::try_current() {
        Ok(rt) => {
            rt.spawn(async move {
                if tokio::task::spawn_blocking(make).await.unwrap_or(false) {
                    again();
                }
            });
            None
        }
        Err(_) => {
            make();
            tile(&p)
        }
    }
}

/// The light in effect (the pointer's lamp rests at the static light; the frontend moves it).
#[derive(Clone, Debug, PartialEq)]
pub struct Light {
    pub mode: &'static str,
    pub dir: [f32; 3],
    pub color: [f32; 3],
    /// Multiplies the shade amplitude (a dim night).
    pub dim: f32,
    /// Why the light is where it is: daytime `sun` (the weather mod's place) or `day` (06:00–18:00 without one);
    /// wallpaper `wallpaper` (its brightest region), `wallpaper_flat` (no light of its own: from above) or
    /// `wallpaper_waiting` (no picture yet).
    pub detail: &'static str,
    /// The wallpaper's light: a lamp at this point of the output (fractions), at `light.height_px`.
    pub lamp: Option<[f32; 2]>,
    /// K61: the spotlight's pin (fractions of the output), at `light.height_px`; its beam aims at the pointer.
    pub pin: Option<[f32; 2]>,
}

/// The weather mod's place, as the night light reads it.
fn place(store: &ConfigStore) -> Option<(f64, f64)> {
    let places =
        kurashi_mod_weather::places::load(&crate::xdg_dir("state").join("weather/places.json"));
    let configured = s(store, "mods.weather.place");
    kurashi_mod_weather::places::effective(&places, &configured, None).map(|p| (p.lat, p.lon))
}

/// Local `(minute of the day, day of the year, UTC offset in minutes)` of `now`.
fn local(now: chrono::DateTime<chrono::Local>) -> (f64, u32, i32) {
    use chrono::{Datelike, Timelike};
    (
        f64::from(now.hour() * 60 + now.minute()) + f64::from(now.second()) / 60.0,
        now.ordinal(),
        now.offset().local_minus_utc() / 60,
    )
}

/// The sun as a light (K59): across the screen from sunrise (left) over noon (top) to sunset (right), its height from
/// the sun's elevation (kept readable), warm when low, a faint cool moon at night.
pub fn sun(place: Option<(f64, f64)>, now: chrono::DateTime<chrono::Local>) -> Light {
    use kurashi_services::nightlight::{sun_elevation, sun_times};
    let (minute, day, offset) = local(now);
    let (rise, set, elevation, detail) = match place {
        Some((lat, lon)) => {
            let e = sun_elevation(lat, lon, day, minute, offset);
            let (rise, set) = sun_times(lat, lon, day, offset)
                .map_or((360.0, 1080.0), |(r, s)| (f64::from(r), f64::from(s)));
            (rise, set, e, "sun")
        }
        None => {
            // A day from 06:00 to 18:00, 50° high at noon.
            let e = 50.0 * ((minute - 360.0) / 720.0 * std::f64::consts::PI).sin();
            (360.0, 1080.0, e, "day")
        }
    };
    let span = if set > rise {
        set - rise
    } else {
        set + 1440.0 - rise
    };
    let since = (minute - rise).rem_euclid(1440.0);
    if elevation < -6.0 || since > span {
        // Night: the moon from above, cool and dim.
        return Light {
            mode: "daytime",
            dir: kurashi_texture::light_dir(0.0, 50.0),
            color: [0.62, 0.71, 0.91],
            dim: 0.6,
            detail,
            lamp: None,
            pin: None,
        };
    }
    let angle = (270.0 + 180.0 * (since / span).clamp(0.0, 1.0)) % 360.0;
    let shown = elevation.clamp(12.0, 65.0);
    // Warm at the horizon, neutral from 20° up.
    let stops: [(f64, [f32; 3]); 4] = [
        (-6.0, [1.0, 0.55, 0.42]),
        (2.0, [1.0, 0.70, 0.45]),
        (10.0, [1.0, 0.86, 0.66]),
        (22.0, [1.0, 0.98, 0.95]),
    ];
    let color = stops
        .windows(2)
        .find(|w| elevation <= w[1].0)
        .map_or(stops[3].1, |w| {
            let t = ((elevation - w[0].0) / (w[1].0 - w[0].0)).clamp(0.0, 1.0) as f32;
            std::array::from_fn(|i| w[0].1[i] + (w[1].1[i] - w[0].1[i]) * t)
        });
    Light {
        mode: "daytime",
        dir: kurashi_texture::light_dir(angle as f32, shown as f32),
        color,
        dim: if elevation < 0.0 { 0.8 } else { 1.0 },
        detail,
        lamp: None,
        pin: None,
    }
}

/// The picture the wallpaper shows now (the theme's picture, else an output's), set by the theme with every publish.
fn shown_picture() -> &'static Mutex<Option<PathBuf>> {
    static SHOWN: OnceLock<Mutex<Option<PathBuf>>> = OnceLock::new();
    SHOWN.get_or_init(Default::default)
}

pub fn set_wallpaper(picture: Option<PathBuf>) {
    *shown_picture().lock().expect("shown picture") = picture;
}

/// The wallpaper's light spot per picture (decoded once, on a blocking thread; the theme is republished when it is
/// known). `Some(None)`: the picture has no light of its own.
fn spots() -> &'static Mutex<HashMap<PathBuf, Option<Option<kurashi_texture::Spot>>>> {
    static SPOTS: OnceLock<Mutex<HashMap<PathBuf, Option<Option<kurashi_texture::Spot>>>>> =
        OnceLock::new();
    SPOTS.get_or_init(Default::default)
}

/// The spot of `picture`: known (`Some`), or being found (`None`).
fn spot_of(picture: &Path) -> Option<Option<kurashi_texture::Spot>> {
    {
        let mut m = spots().lock().expect("spots");
        match m.get(picture) {
            Some(Some(known)) => return Some(*known),
            Some(None) => return None,
            None => {
                m.insert(picture.to_path_buf(), None);
            }
        }
    }
    let path = picture.to_path_buf();
    let find = move || {
        let spot = image::open(&path)
            .ok()
            .and_then(|img| kurashi_texture::light_spot(&img.to_rgba8()));
        spots().lock().expect("spots").insert(path, Some(spot));
    };
    match tokio::runtime::Handle::try_current() {
        Ok(rt) => {
            rt.spawn(async move {
                let _ = tokio::task::spawn_blocking(find).await;
                again();
            });
            None
        }
        Err(_) => {
            find();
            spot_of(picture)
        }
    }
}

/// The wallpaper's light (K59): a lamp at the picture's brightest region, in its colour (halfway to white, so the
/// shell's palette stays itself); a flat picture lights from above, as does a missing one until it is there.
fn wallpaper_light(store: &ConfigStore) -> Light {
    let from_above = |detail| Light {
        mode: "wallpaper",
        dir: kurashi_texture::light_dir(0.0, f(store, "theme.light.elevation", 40.0) as f32),
        color: [1.0, 1.0, 1.0],
        dim: 1.0,
        detail,
        lamp: None,
        pin: None,
    };
    let picture = shown_picture().lock().expect("shown picture").clone();
    let Some(picture) = picture else {
        return from_above("wallpaper_waiting");
    };
    match spot_of(&picture) {
        None => from_above("wallpaper_waiting"),
        Some(None) => from_above("wallpaper_flat"),
        Some(Some(spot)) => {
            // The direction from the screen's middle toward the spot, for what needs one direction (swatches).
            let angle = (spot.x - 0.5)
                .atan2(0.5 - spot.y)
                .to_degrees()
                .rem_euclid(360.0);
            Light {
                mode: "wallpaper",
                dir: kurashi_texture::light_dir(
                    angle,
                    f(store, "theme.light.elevation", 40.0) as f32,
                ),
                color: spot.color.map(|c| 0.5 + 0.5 * c),
                dim: 1.0,
                detail: "wallpaper",
                lamp: Some([spot.x, spot.y]),
                pin: None,
            }
        }
    }
}

/// The light of the mode in effect, in its own (natural) colour.
fn natural_light(store: &ConfigStore, now: chrono::DateTime<chrono::Local>) -> Light {
    let fixed = |mode| Light {
        mode,
        dir: kurashi_texture::light_dir(
            f(store, "theme.light.angle", 315.0) as f32,
            f(store, "theme.light.elevation", 40.0) as f32,
        ),
        color: [1.0, 1.0, 1.0],
        dim: 1.0,
        detail: "",
        lamp: None,
        pin: None,
    };
    match s(store, "theme.light.mode").as_str() {
        "daytime" => sun(place(store), now),
        "pointer" => fixed("pointer"),
        "wallpaper" => wallpaper_light(store),
        "spotlight" => Light {
            pin: Some(kurashi_texture::pin(
                f(store, "theme.light.angle", 315.0) as f32
            )),
            ..fixed("spotlight")
        },
        _ => fixed("static"),
    }
}

/// K61: the named light colours (`theme.light.color`); the one table Settings' swatches read too (`appearance`).
const LIGHT_COLORS: [(&str, [f32; 3]); 3] = [
    ("white", [1.0, 1.0, 1.0]),
    ("warm", [1.0, 0.86, 0.66]),
    ("cool", [0.78, 0.87, 1.0]),
];

fn hex(c: [f32; 3]) -> String {
    let [r, g, b] = c.map(|v| (v.clamp(0.0, 1.0) * 255.0).round() as u8);
    format!("#{r:02x}{g:02x}{b:02x}")
}

fn custom_light(store: &ConfigStore) -> Option<[f32; 3]> {
    kurashi_theme::color::Rgb::parse(&s(store, "theme.light.color_custom")).map(lin)
}

pub fn light(store: &ConfigStore, now: chrono::DateTime<chrono::Local>) -> Light {
    let mut lt = natural_light(store, now);
    // K61: the light's colour; natural keeps the mode's own (white, the sun's, the wallpaper's).
    let pick = s(store, "theme.light.color");
    let own = match pick.as_str() {
        "custom" => custom_light(store),
        name => LIGHT_COLORS
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(_, c)| *c),
    };
    if let Some(c) = own {
        lt.color = c;
    }
    lt
}

/// K61 (row 340): every light colour as the daemon resolves it, for Settings' swatches: `{natural, white, warm, cool,
/// custom}` in hex, natural the mode's own now.
pub fn light_colors(store: &ConfigStore, now: chrono::DateTime<chrono::Local>) -> Value {
    let mut m = Map::new();
    m.insert(
        "natural".into(),
        json!(hex(natural_light(store, now).color)),
    );
    for (n, c) in LIGHT_COLORS {
        m.insert(n.into(), json!(hex(c)));
    }
    m.insert(
        "custom".into(),
        json!(hex(custom_light(store).unwrap_or([1.0, 1.0, 1.0]))),
    );
    Value::Object(m)
}

/// Whether the light needs the wallpaper's picture (the theme then holds the wallpaper mod's document).
pub fn wants_wallpaper(store: &ConfigStore) -> bool {
    kind(store).is_some() && s(store, "theme.light.mode") == "wallpaper"
}

/// Whether the daytime light is wanted (the theme's 5-minute tick runs only then).
pub fn wants_sun(store: &ConfigStore) -> bool {
    kind(store).is_some() && s(store, "theme.light.mode") == "daytime"
}

fn kind(store: &ConfigStore) -> Option<Kind> {
    Kind::parse(&s(store, "theme.texture.kind"))
}

fn params(store: &ConfigStore, kind: Kind) -> Params {
    Params {
        kind,
        wrinkles: (f(store, "theme.texture.wrinkles", 0.0) as f32 * 20.0).round() / 20.0,
        tint: b(store, "theme.texture.tint"),
        device_scale: device_scale(),
        cracks: (f(store, "theme.texture.cracks", 0.0) as f32 * 20.0).round() / 20.0,
        crack_style: CrackStyle::parse(&s(store, "theme.texture.crack_style")),
    }
}

/// K61: the wallpaper's own material (`theme.texture.wallpaper.own`): its tile parameters, strength and scale; the
/// shell's otherwise.
fn wallpaper_params(store: &ConfigStore) -> Option<(Params, f64, f64)> {
    if b(store, "theme.texture.wallpaper.own") {
        let kind = Kind::parse(&s(store, "theme.texture.wallpaper.kind"))?;
        let q = |k: &str| (f(store, k, 0.0) as f32 * 20.0).round() / 20.0;
        Some((
            Params {
                kind,
                wrinkles: q("theme.texture.wallpaper.wrinkles"),
                cracks: q("theme.texture.wallpaper.cracks"),
                ..params(store, kind)
            },
            f(store, "theme.texture.wallpaper.strength", 0.5),
            f(store, "theme.texture.wallpaper.scale", 1.0),
        ))
    } else {
        let kind = kind(store)?;
        Some((
            params(store, kind),
            f(store, "theme.texture.strength", 0.5),
            f(store, "theme.texture.scale", 1.0),
        ))
    }
}

/// K61: the relief shadows in effect: the material's own under auto, else on or off.
fn shadow_of(store: &ConfigStore, kind: Kind) -> f32 {
    match s(store, "theme.texture.shadows").as_str() {
        "on" => 1.0,
        "off" => 0.0,
        _ => kurashi_texture::material(kind).shadow,
    }
}

/// K61 (I169): highlights read stronger than shade on a dark ground, so the light half is weighed down there.
fn lit_on(ground: [f32; 3]) -> f32 {
    let l = 0.2126 * ground[0] + 0.7152 * ground[1] + 0.0722 * ground[2];
    if l < 0.3 { 0.6 } else { 1.0 }
}

fn rgb(t: &Map<String, Value>, key: &str) -> kurashi_theme::color::Rgb {
    t.get(key)
        .and_then(Value::as_str)
        .and_then(kurashi_theme::color::Rgb::parse)
        .unwrap_or(kurashi_theme::color::Rgb(128, 128, 128))
}

fn lin(c: kurashi_theme::color::Rgb) -> [f32; 3] {
    [c.0, c.1, c.2].map(|v| f32::from(v) / 255.0)
}

/// The largest amplitude up to `want` at which `fg` keeps [`TEXT_CONTRAST`] on each ground both shaded (multiplied by
/// `1 − amp`) and lit (screened toward the light by `amp`).
pub fn legible_amp(want: f64, fg: [f32; 3], grounds: &[[f32; 3]], light: [f32; 3]) -> f64 {
    use kurashi_theme::color::{Rgb, contrast};
    let rgb = |c: [f32; 3]| {
        let [r, g, b] = c.map(|v| (v.clamp(0.0, 1.0) * 255.0).round() as u8);
        Rgb(r, g, b)
    };
    let ok = |amp: f64| {
        let a = amp as f32;
        grounds.iter().all(|g| {
            let dark = g.map(|v| v * (1.0 - a));
            let lit: [f32; 3] = std::array::from_fn(|i| light[i] * a + g[i] * (1.0 - a));
            contrast(rgb(fg), rgb(dark)) >= TEXT_CONTRAST
                && contrast(rgb(fg), rgb(lit)) >= TEXT_CONTRAST
        })
    };
    let mut amp = want;
    while amp > 0.0 && !ok(amp) {
        amp -= 0.005;
    }
    amp.max(0.0)
}

/// Adds the texture and light tokens to a resolved token map; notes for provenance.
pub fn tokens(
    store: &ConfigStore,
    t: &mut Map<String, Value>,
    now: chrono::DateTime<chrono::Local>,
) -> Vec<String> {
    let mut notes = vec![];
    let lt = light(store, now);
    t.insert("light.mode".into(), json!(lt.mode));
    t.insert("light.dir".into(), json!(lt.dir));
    t.insert("light.color".into(), json!(hex(lt.color)));
    t.insert("light.lamp".into(), json!(lt.lamp));
    t.insert("light.pin".into(), json!(lt.pin));
    t.insert(
        "light.beam".into(),
        json!(f(store, "theme.light.beam", 35.0)),
    );
    t.insert(
        "light.height_px".into(),
        json!(30.0 + f(store, "theme.light.elevation", 40.0) * 5.0),
    );
    let scope = s(store, "theme.texture.scope");
    let ready = kind(store).and_then(|k| tile(&params(store, k)).map(|(p, tl)| (k, p, tl)));
    let Some((kind, path, tl)) = ready else {
        for (k, v) in [
            ("texture.map", json!("")),
            ("texture.ink_map", json!("")),
            ("texture.tile_px", json!(0)),
            ("texture.tile_logical", json!(0)),
            ("texture.scale", json!(1.0)),
            ("texture.amp", json!(0.0)),
            ("texture.gloss", json!(0.0)),
            ("texture.shininess", json!(1.0)),
            ("texture.ink", json!("#000000")),
            ("texture.ink_alpha", json!(0.0)),
            ("texture.text", json!(false)),
            ("texture.shell", json!(false)),
            ("texture.overlay", json!(false)),
            ("texture.depth", json!(1.0)),
            ("texture.shadow", json!(0.0)),
            ("texture.height_map", json!("")),
            ("texture.relief_px", json!(0.0)),
            ("texture.lit", json!(1.0)),
            ("texture.controls", json!(false)),
            ("texture.sheet", json!("carried")),
        ] {
            t.insert(k.into(), v);
        }
        if kind(store).is_some() {
            notes.push("texture: generating".into());
        }
        return notes;
    };
    let m = kurashi_texture::material(kind);
    let want = f(store, "theme.texture.strength", 0.5) * AMP_FULL * f64::from(lt.dim);
    let grounds = [
        lin(rgb(t, "color.surface")),
        lin(rgb(t, "color.surface_container")),
        lin(rgb(t, "color.surface_container_high")),
    ];
    let amp = legible_amp(want, lin(rgb(t, "color.on_surface")), &grounds, lt.color);
    if amp + 1e-9 < want {
        notes.push(format!(
            "texture: strength capped for legible text ({want:.3} → {amp:.3})"
        ));
    }
    let ink = match m.ink_role {
        InkRole::Secondary => rgb(t, "color.secondary"),
        InkRole::OnSurface | InkRole::None => rgb(t, "color.on_surface"),
    };
    let tint = b(store, "theme.texture.tint") && m.ink_role != InkRole::None;
    t.insert("texture.map".into(), json!(path.to_string_lossy()));
    let ink_map = kurashi_texture::ink_path(&path);
    t.insert(
        "texture.ink_map".into(),
        json!(if tint && ink_map.is_file() {
            ink_map.to_string_lossy().into_owned()
        } else {
            String::new()
        }),
    );
    t.insert("texture.tile_px".into(), json!(tl.size));
    t.insert("texture.tile_logical".into(), json!(tl.logical));
    t.insert(
        "texture.scale".into(),
        json!(f(store, "theme.texture.scale", 1.0)),
    );
    t.insert("texture.amp".into(), json!((amp * 1000.0).round() / 1000.0));
    t.insert("texture.gloss".into(), json!(m.gloss));
    t.insert("texture.shininess".into(), json!(m.shininess));
    t.insert("texture.ink".into(), json!(ink.hex()));
    t.insert(
        "texture.ink_alpha".into(),
        json!(if tint { m.ink_alpha } else { 0.0 }),
    );
    t.insert("texture.text".into(), json!(b(store, "theme.texture.text")));
    t.insert(
        "texture.shell".into(),
        json!(scope == "shell" || scope == "shell_wallpaper"),
    );
    t.insert("texture.overlay".into(), json!(scope == "everything"));
    // K61: depth, relief shadows (the height map only while they are on), the dark ground's balance, controls, sheet.
    let depth = f(store, "theme.texture.depth", 1.0);
    let shadow = shadow_of(store, kind);
    let height_map = kurashi_texture::height_path(&path);
    t.insert("texture.depth".into(), json!(depth));
    t.insert("texture.shadow".into(), json!(f64::from(shadow)));
    t.insert(
        "texture.height_map".into(),
        json!(if shadow > 0.0 && height_map.is_file() {
            height_map.to_string_lossy().into_owned()
        } else {
            String::new()
        }),
    );
    t.insert(
        "texture.relief_px".into(),
        json!(
            ((f64::from(tl.relief) * depth * f(store, "theme.texture.scale", 1.0)) * 1000.0)
                .round()
                / 1000.0
        ),
    );
    t.insert(
        "texture.lit".into(),
        json!((f64::from(lit_on(grounds[0])) * 100.0).round() / 100.0),
    );
    t.insert(
        "texture.controls".into(),
        json!(b(store, "theme.texture.controls")),
    );
    t.insert(
        "texture.sheet".into(),
        json!(match s(store, "theme.texture.sheet").as_str() {
            "fixed" => "fixed",
            "separate" => "separate",
            _ => "carried",
        }),
    );
    notes.push(format!("texture: {} ({})", kind.name(), lt.mode));
    notes
}

/// What the wallpaper bake needs from the theme in effect: the tile, its shading, the user's scale. `None` when the
/// scope leaves the wallpaper alone, or the tile is not ready yet.
pub fn wallpaper_shading(
    store: &ConfigStore,
    tokens: &Map<String, Value>,
) -> Option<(Arc<Tile>, Shading, f32)> {
    let scope = s(store, "theme.texture.scope");
    if scope != "wallpaper" && scope != "shell_wallpaper" {
        return None;
    }
    let (wp, strength, scale) = wallpaper_params(store)?;
    let (_, tl) = tile(&wp)?;
    let own = b(store, "theme.texture.wallpaper.own");
    let num = |k: &str| tokens.get(k).and_then(Value::as_f64).unwrap_or(0.0) as f32;
    let m = kurashi_texture::material(wp.kind);
    let depth = f(store, "theme.texture.depth", 1.0) as f32;
    let pin = tokens
        .get("light.pin")
        .and_then(Value::as_array)
        .filter(|a| a.len() == 2)
        .map(|a| {
            [
                a[0].as_f64().unwrap_or(0.5) as f32,
                a[1].as_f64().unwrap_or(0.0) as f32,
            ]
        });
    let dir = tokens
        .get("light.dir")
        .and_then(Value::as_array)
        .map(|a| std::array::from_fn(|i| a.get(i).and_then(Value::as_f64).unwrap_or(0.0) as f32))?;
    // The wallpaper carries no text: its own material is not capped for legibility (the shell's keeps its cap, so the
    // baked relief and the shell's agree).
    let amp = if own {
        (strength * AMP_FULL) as f32
    } else {
        num("texture.amp")
    };
    let lamp = tokens
        .get("light.lamp")
        .and_then(Value::as_array)
        .filter(|a| a.len() == 2)
        .map(|a| {
            [
                a[0].as_f64().unwrap_or(0.5) as f32,
                a[1].as_f64().unwrap_or(0.0) as f32,
                num("light.height_px").max(1.0),
            ]
        })
        .or(pin.map(|p| [p[0], p[1], num("light.height_px").max(1.0)]));
    let sh = Shading {
        amp,
        gloss: m.gloss,
        shininess: m.shininess.max(1.0),
        ink: lin(rgb(tokens, "texture.ink")),
        ink_alpha: if own {
            if b(store, "theme.texture.tint") && m.ink_role != InkRole::None {
                m.ink_alpha
            } else {
                0.0
            }
        } else {
            num("texture.ink_alpha")
        },
        light_dir: dir,
        light_color: lin(rgb(tokens, "light.color")),
        lamp,
        depth,
        shadow: shadow_of(store, wp.kind),
        relief_px: tl.relief * depth * scale as f32,
        lit: 1.0,
        // The bake keeps the spotlight at rest: aimed at the output's middle.
        beam: pin.map(|_| Beam::new([0.5, 0.5], num("light.beam").max(1.0))),
    };
    Some((tl, sh, (scale as f32).max(0.1)))
}

/// Bakes the texture into `picture` for an output of `size` at `scale` (cached by everything that changes the bytes);
/// the original picture is never written.
pub fn bake_file(
    picture: &Path,
    size: (u32, u32),
    output_scale: f32,
    tile: &Tile,
    sh: &Shading,
    user_scale: f32,
) -> Result<PathBuf, kurashi_texture::Error> {
    use std::hash::{Hash, Hasher};
    let meta = std::fs::metadata(picture)?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    picture.hash(&mut h);
    meta.len().hash(&mut h);
    meta.modified().ok().hash(&mut h);
    size.hash(&mut h);
    format!(
        "{output_scale:?}{user_scale:?}{sh:?}{}{}",
        tile.size,
        tile.rgba.len()
    )
    .hash(&mut h);
    tile.rgba.iter().step_by(997).for_each(|b| b.hash(&mut h));
    let dir = cache_dir().join("wallpaper");
    let out = dir.join(format!("{:016x}.png", h.finish()));
    if out.is_file() {
        return Ok(out);
    }
    std::fs::create_dir_all(&dir)?;
    let img = image::open(picture)?;
    // Cover the output as awww's default fit does; the bake is at the output's pixels, so the sheet lines up.
    let filled = img
        .resize_to_fill(
            size.0.max(1),
            size.1.max(1),
            image::imageops::FilterType::Lanczos3,
        )
        .to_rgba8();
    let baked = kurashi_texture::bake(&filled, tile, sh, output_scale, user_scale);
    let tmp = out.with_extension("png.tmp");
    baked.save_with_format(&tmp, image::ImageFormat::Png)?;
    std::fs::rename(&tmp, &out)?;
    // Keep the cache small: the newest dozen bakes.
    if let Ok(rd) = std::fs::read_dir(&dir) {
        let mut files: Vec<_> = rd
            .filter_map(Result::ok)
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
            .collect();
        files.sort();
        for (_, p) in files.iter().rev().skip(12) {
            let _ = std::fs::remove_file(p);
        }
    }
    Ok(out)
}

/// Settings' material cards want swatches (it watches `theme.previews`); none are made otherwise (Ma).
static SWATCHES_WANTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static SWATCHES_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn want_swatches(on: bool) {
    if SWATCHES_WANTED.swap(on, Ordering::Relaxed) != on && on {
        again();
    }
}

/// The swatch side in pixels (a card shows it at about half: sharp on a scale-2 output).
const SWATCH_PX: u32 = 128;

/// Settings' material cards (K59): every kind as a small lit square on the container colour, in the light, tint and
/// wrinkles in effect — `[{name, image}]`, `image` `""` until it is made (one blocking task makes the missing ones, then
/// the theme is republished). Empty while nobody watches.
pub fn swatches(store: &ConfigStore, t: &Map<String, Value>) -> Value {
    if !SWATCHES_WANTED.load(Ordering::Relaxed) {
        return json!([]);
    }
    let lt = light(store, chrono::Local::now());
    let base = lin(rgb(t, "color.surface_container_high"));
    let grounds = [base];
    let amp = legible_amp(0.12, lin(rgb(t, "color.on_surface")), &grounds, lt.color).max(0.06);
    let tint = b(store, "theme.texture.tint");
    let wrinkles = (f(store, "theme.texture.wrinkles", 0.0) as f32 * 20.0).round() / 20.0;
    let cracks = (f(store, "theme.texture.cracks", 0.0) as f32 * 20.0).round() / 20.0;
    let crack_style = CrackStyle::parse(&s(store, "theme.texture.crack_style"));
    let jobs: Vec<(Kind, PathBuf, Shading)> = Kind::ALL
        .into_iter()
        .map(|kind| {
            let m = kurashi_texture::material(kind);
            let ink = match m.ink_role {
                InkRole::Secondary => rgb(t, "color.secondary"),
                InkRole::OnSurface | InkRole::None => rgb(t, "color.on_surface"),
            };
            let sh = Shading {
                amp: amp as f32,
                gloss: m.gloss,
                shininess: m.shininess,
                ink: lin(ink),
                ink_alpha: if tint { m.ink_alpha } else { 0.0 },
                light_dir: lt.dir,
                light_color: lt.color,
                lamp: None,
                depth: f(store, "theme.texture.depth", 1.0) as f32,
                shadow: shadow_of(store, kind),
                // A swatch shows the tile at 1:1; its relief is set once the tile is known (below).
                relief_px: 0.0,
                lit: lit_on(base),
                beam: None,
            };
            let name = {
                use std::hash::{Hash, Hasher};
                let mut h = std::collections::hash_map::DefaultHasher::new();
                format!(
                    "{sh:?}{wrinkles}{cracks}{crack_style:?}{tint}{base:?}{}",
                    kurashi_texture::generate_version()
                )
                .hash(&mut h);
                format!("{}-{:016x}.png", kind.name(), h.finish())
            };
            (kind, cache_dir().join("swatch").join(name), sh)
        })
        .collect();
    let missing: Vec<_> = jobs
        .iter()
        .filter(|(_, p, _)| !p.is_file())
        .cloned()
        .collect();
    if !missing.is_empty() && !SWATCHES_RUNNING.swap(true, Ordering::Relaxed) {
        let make = move || {
            for (kind, path, sh) in missing {
                let p = Params {
                    kind,
                    wrinkles,
                    tint,
                    device_scale: 1.0,
                    cracks,
                    crack_style,
                };
                let Ok((_, tile)) = kurashi_texture::tile_file(&cache_dir(), &p) else {
                    continue;
                };
                let sh = Shading {
                    relief_px: tile.relief * sh.depth,
                    ..sh
                };
                let img = kurashi_texture::preview(&tile, &sh, base, SWATCH_PX, 1.0);
                let _ = std::fs::create_dir_all(path.parent().unwrap_or(Path::new(".")));
                let tmp = path.with_extension("png.tmp");
                if img.save_with_format(&tmp, image::ImageFormat::Png).is_ok() {
                    let _ = std::fs::rename(&tmp, &path);
                }
            }
            SWATCHES_RUNNING.store(false, Ordering::Relaxed);
        };
        match tokio::runtime::Handle::try_current() {
            Ok(rt) => {
                rt.spawn(async move {
                    let _ = tokio::task::spawn_blocking(make).await;
                    again();
                });
            }
            Err(_) => make(),
        }
    }
    Value::Array(
        jobs.iter()
            .map(|(kind, path, _)| {
                json!({
                    "name": kind.name(),
                    "image": if path.is_file() { path.to_string_lossy().into_owned() } else { String::new() },
                })
            })
            .collect(),
    )
}

/// What the wallpaper bake uses now; `None` while the wallpaper is not a texture scope (pictures go through unchanged).
#[derive(Clone)]
struct Bake {
    tile: Arc<Tile>,
    sh: Shading,
    scale: f32,
}

fn bake_state() -> &'static Mutex<Option<Bake>> {
    static BAKE: OnceLock<Mutex<Option<Bake>>> = OnceLock::new();
    BAKE.get_or_init(Default::default)
}

fn bake_tx() -> &'static tokio::sync::watch::Sender<u64> {
    static TX: OnceLock<tokio::sync::watch::Sender<u64>> = OnceLock::new();
    TX.get_or_init(|| tokio::sync::watch::channel(0).0)
}

/// Called with every theme the daemon publishes: when what the bake would do changes, the wallpaper mod is told to show
/// its pictures again (through [`picture_filter`]).
pub fn update_bake(store: &ConfigStore, tokens: &Map<String, Value>) {
    let next = wallpaper_shading(store, tokens).map(|(tile, sh, scale)| Bake { tile, sh, scale });
    let mut cur = bake_state().lock().expect("bake state");
    let same = match (&*cur, &next) {
        (None, None) => true,
        (Some(a), Some(b)) => Arc::ptr_eq(&a.tile, &b.tile) && a.sh == b.sh && a.scale == b.scale,
        _ => false,
    };
    if !same {
        *cur = next;
        drop(cur);
        bake_tx().send_modify(|v| *v += 1);
    }
}

struct Filter;

impl kurashi_mod_api::PictureFilter for Filter {
    fn filter(&self, picture: &Path, size: (u32, u32), scale: f32) -> PathBuf {
        let Some(b) = bake_state().lock().expect("bake state").clone() else {
            return picture.to_path_buf();
        };
        bake_file(picture, size, scale, &b.tile, &b.sh, b.scale).unwrap_or_else(|e| {
            tracing::warn!(picture = %picture.display(), error = %e, "texture bake failed; the picture is shown as is");
            picture.to_path_buf()
        })
    }

    fn changes(&self) -> tokio::sync::watch::Receiver<u64> {
        bake_tx().subscribe()
    }
}

/// The host's picture filter for wallpaper mods (K59).
pub fn picture_filter() -> Arc<dyn kurashi_mod_api::PictureFilter> {
    Arc::new(Filter)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn the_sun_crosses_the_screen_from_left_to_right() {
        let tokyo = Some((35.6895, 139.6917));
        let at = |h, m| {
            chrono::Local
                .with_ymd_and_hms(2026, 6, 21, h, m, 0)
                .unwrap()
        };
        // Run in the machine's zone; only the shape is asserted.
        let morning = sun(None, at(7, 0));
        let noon = sun(None, at(12, 0));
        let evening = sun(None, at(17, 0));
        assert!(morning.dir[0] < -0.3, "morning from the left: {morning:?}");
        assert!(
            noon.dir[1] < -0.3 && noon.dir[0].abs() < 0.2,
            "noon from above: {noon:?}"
        );
        assert!(evening.dir[0] > 0.3, "evening from the right: {evening:?}");
        // Low sun is warm, noon neutral.
        assert!(morning.color[2] < noon.color[2]);
        let night = sun(None, at(23, 30));
        assert!(night.dim < 1.0 && night.color[2] > night.color[0]);
        assert_eq!(sun(tokyo, at(12, 0)).detail, "sun");
        assert_eq!(noon.detail, "day");
    }

    fn store_with(root: &std::path::Path, toml: &str) -> std::sync::Arc<ConfigStore> {
        std::fs::create_dir_all(root.join("config")).unwrap();
        std::fs::write(root.join("config/config.toml"), toml).unwrap();
        ConfigStore::open(
            crate::hub::Hub::new(),
            kurashi_schema::v1::registry(),
            kurashi_config::Paths::rooted(root),
            kurashi_config::Options::default(),
        )
    }

    /// The tokens follow the config; the wallpaper scope bakes a copy of the output's size, the shell scope leaves the
    /// picture alone, and the bake filter is told about the change.
    #[test]
    fn tokens_and_the_wallpaper_bake_follow_the_scope() {
        let root = std::env::temp_dir().join(format!("kurashi-texture-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        set_cache_dir(root.join("cache"));
        let pic = root.join("pic.png");
        std::fs::create_dir_all(&root).unwrap();
        image::RgbImage::from_pixel(64, 36, image::Rgb([90, 120, 160]))
            .save(&pic)
            .unwrap();
        let now = chrono::Local::now();
        let toml = |scope: &str| {
            format!(
                "schema_version = 2\n[theme.texture]\nkind = \"paper_grid\"\nscope = \"{scope}\"\nstrength = 1.0\n"
            )
        };
        let store = store_with(&root, &toml("wallpaper"));
        let mut t = Map::new();
        t.insert("color.surface".into(), json!("#f3eee3"));
        t.insert("color.surface_container".into(), json!("#ece6da"));
        t.insert("color.surface_container_high".into(), json!("#e6dfd2"));
        t.insert("color.on_surface".into(), json!("#2b2a2e"));
        t.insert("color.secondary".into(), json!("#284f7e"));
        tokens(&store, &mut t, now);
        assert!(
            t["texture.map"].as_str().unwrap().ends_with(".png"),
            "{t:?}"
        );
        assert!(t["texture.amp"].as_f64().unwrap() > 0.0);
        assert_eq!(t["texture.ink"], "#284f7e");
        assert_eq!(t["texture.shell"], false);
        assert_eq!(t["texture.overlay"], false);
        assert_eq!(t["light.mode"], "static");

        let changes = picture_filter().changes();
        let seen = *changes.borrow();
        update_bake(&store, &t);
        assert!(*changes.borrow() > seen, "the filter is told");
        let baked = picture_filter().filter(&pic, (320, 180), 1.0);
        assert_ne!(baked, pic);
        let img = image::open(&baked).unwrap();
        assert_eq!((img.width(), img.height()), (320, 180));

        let store = store_with(&root, &toml("shell"));
        let mut t2 = t.clone();
        tokens(&store, &mut t2, now);
        assert_eq!(t2["texture.shell"], true);
        update_bake(&store, &t2);
        assert_eq!(picture_filter().filter(&pic, (320, 180), 1.0), pic);
        let _ = std::fs::remove_dir_all(&root);
    }

    /// K61: depth, relief shadows (auto for paint, the height map with them), the spotlight's pin, the light's colour,
    /// controls and the sheet as tokens; the dark ground weighs the light half down.
    #[test]
    fn wave_32_tokens_follow_their_keys() {
        let root = std::env::temp_dir().join(format!("kurashi-texture-w32-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        set_cache_dir(root.join("cache"));
        std::fs::create_dir_all(&root).unwrap();
        let store = store_with(
            &root,
            "schema_version = 2\n[theme.texture]\nkind = \"paint\"\ndepth = 2.0\ncontrols = true\nsheet = \"fixed\"\n\
             [theme.light]\nmode = \"spotlight\"\nangle = 0\nbeam = 25\ncolor = \"warm\"\n",
        );
        let mut t = Map::new();
        t.insert("color.surface".into(), json!("#1d2230"));
        t.insert("color.surface_container".into(), json!("#232838"));
        t.insert("color.surface_container_high".into(), json!("#2a3042"));
        t.insert("color.on_surface".into(), json!("#e8ecf6"));
        t.insert("color.secondary".into(), json!("#9ab4e8"));
        tokens(&store, &mut t, chrono::Local::now());
        assert_eq!(t["texture.depth"], 2.0);
        assert_eq!(t["texture.shadow"], 1.0, "paint casts shadows under auto");
        assert!(
            t["texture.height_map"]
                .as_str()
                .unwrap()
                .ends_with("-height.png"),
            "{t:?}"
        );
        assert!(t["texture.relief_px"].as_f64().unwrap() > 0.0);
        assert_eq!(t["texture.lit"], 0.6, "a dark ground");
        assert_eq!(t["texture.controls"], true);
        assert_eq!(t["texture.sheet"], "fixed");
        assert_eq!(t["light.mode"], "spotlight");
        assert_eq!(t["light.pin"], json!([0.5, 0.0]));
        assert_eq!(t["light.beam"], 25.0);
        assert_eq!(t["light.color"], "#ffdba8");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The wallpaper's light: a lamp at the picture's bright corner, warm like it; from above while there is no picture.
    #[test]
    fn the_wallpaper_light_is_a_lamp_at_its_brightest_place() {
        let root = std::env::temp_dir().join(format!("kurashi-wall-light-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let pic = root.join("sunset.png");
        let mut img = image::RgbImage::from_pixel(320, 180, image::Rgb([20, 24, 40]));
        for y in 20..60 {
            for x in 30..80 {
                img.put_pixel(x, y, image::Rgb([255, 190, 120]));
            }
        }
        img.save(&pic).unwrap();
        let store = store_with(
            &root,
            "schema_version = 2\n[theme.texture]\nkind = \"paper\"\n[theme.light]\nmode = \"wallpaper\"\n",
        );
        set_wallpaper(None);
        let waiting = light(&store, chrono::Local::now());
        assert_eq!((waiting.detail, waiting.lamp), ("wallpaper_waiting", None));
        set_wallpaper(Some(pic));
        let lit = light(&store, chrono::Local::now());
        assert_eq!(lit.detail, "wallpaper");
        let [x, y] = lit.lamp.expect("a lamp");
        assert!(
            (0.1..0.25).contains(&x) && (0.1..0.35).contains(&y),
            "{x} {y}"
        );
        assert!(lit.color[0] > lit.color[2], "warm: {:?}", lit.color);
        // Toward the top left from the middle.
        assert!(lit.dir[0] < 0.0 && lit.dir[1] < 0.0, "{:?}", lit.dir);
        set_wallpaper(None);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_cap_keeps_text_legible() {
        // Dark text on light paper: a deep shade would sink the paper toward the ink.
        let fg = [0.11, 0.25, 0.6];
        let paper = [[0.95, 0.93, 0.89]];
        let amp = legible_amp(0.18, fg, &paper, [1.0, 1.0, 1.0]);
        assert!(amp > 0.0 && amp <= 0.18);
        // Already-low contrast leaves no room at all.
        assert_eq!(
            legible_amp(0.18, [0.5, 0.5, 0.5], &[[0.55, 0.55, 0.55]], [1.0; 3]),
            0.0
        );
    }
}
