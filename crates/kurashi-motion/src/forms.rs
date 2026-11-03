//! Forms: what progress does to a whole surface (K83, `docs/ux/motion-engine.md` §5–§6), and where each may run.
//!
//! The table is the `motion.forms` meta the theme document publishes and the `motion.forms` choice source Settings lists.
//! Forms whose frontend card has not merged yet are here already with `available: false`: they are not offered, a
//! value naming one is not in effect (`config.diag.form.unavailable`) and the resolver falls back past it. A form card
//! flips its own row's last field — one line per form.

use serde_json::{Value, json};

/// The surface classes forms apply to (`theme.motion.form.<surface>`, brief §6). The island takes every form (D3).
pub const SURFACES: [&str; 12] = [
    "island", "panel", "peek", "launcher", "centre", "toast", "sidebar", "dock", "bar", "osd",
    "menu", "dialog",
];

/// Why a value naming a form that has no frontend yet is not in effect.
pub const REASON_UNAVAILABLE: &str = "config.diag.form.unavailable";
/// Why a form is not in effect on a surface class it cannot serve.
pub const REASON_SURFACE: &str = "config.diag.form.surface";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Family {
    /// The silhouette stays the live vector shape (join, neck, shadow, material and blur follow every frame).
    Shape,
    /// The card is captured into one layer while it moves and warped (GridMesh vertex warps, fragment passes).
    Sheet,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Retarget {
    /// A shape morphs into the next one from where it is.
    Morph,
    /// The form finishes on `fast`, then the shape morphs.
    Finish,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tier {
    /// Plain transforms, no layer.
    Transform,
    /// One offscreen layer while it moves.
    Layer,
    /// A layer drawn through a vertex mesh.
    Mesh,
}

/// What reduce motion and the photosensitivity rules key on.
pub const VESTIBULAR: u8 = 1;
pub const FLASH: u8 = 2;

/// Every surface class.
const ALL: u16 = 0xfff;
const fn s(name: &str) -> u16 {
    let b = name.as_bytes();
    // The surface's index in SURFACES, by its first two letters (unique among them).
    match (b[0], b[1]) {
        (b'i', _) => 1,
        (b'p', b'a') => 1 << 1,
        (b'p', b'e') => 1 << 2,
        (b'l', _) => 1 << 3,
        (b'c', _) => 1 << 4,
        (b't', _) => 1 << 5,
        (b's', _) => 1 << 6,
        (b'd', b'o') => 1 << 7,
        (b'b', _) => 1 << 8,
        (b'o', _) => 1 << 9,
        (b'm', _) => 1 << 10,
        (b'd', b'i') => 1 << 11,
        _ => panic!("unknown surface"),
    }
}
/// The surfaces whose live shape morphs out of its origin — the Stage's island views, panels and peeks, BarMorph's
/// launcher and centre: what liquid needs (the origin's own rect and radius flow into the card).
const MORPHS: u16 = s("island") | s("panel") | s("peek") | s("launcher") | s("centre");

pub struct FormMeta {
    pub id: &'static str,
    pub family: Family,
    surfaces: u16,
    pub retarget: Retarget,
    /// Whether progress past 1 (an overshooting curve) is drawn, or clamped.
    pub overshoot: bool,
    flags: u8,
    pub tier: Tier,
    /// Whether the frontend draws it (its card merged).
    pub available: bool,
}

use Family::{Shape, Sheet};
use Retarget::{Finish, Morph};
use Tier::{Layer, Mesh, Transform};

/// One row of [`FORMS`], positional so the table reads as a table.
#[allow(clippy::too_many_arguments)]
const fn f(
    id: &'static str,
    family: Family,
    surfaces: u16,
    retarget: Retarget,
    overshoot: bool,
    flags: u8,
    tier: Tier,
    available: bool,
) -> FormMeta {
    FormMeta {
        id,
        family,
        surfaces: surfaces | 1, // every form serves the island (D3)
        retarget,
        overshoot,
        flags,
        tier,
        available,
    }
}

/// Every form (brief §5). Today's forms (Entrance, K74's grow) are available; the rest flip `available` as their card
/// (W59.3–W59.8) lands. `none` is the cut (motion off, or a surface the user wants still).
#[rustfmt::skip]
pub const FORMS: &[FormMeta] = &[
    //   id          family surfaces                                             retarget overshoot flags       tier       available
    f("none",     Shape, ALL,                                                   Morph,  false, 0,          Transform, true),
    f("grow",     Shape, ALL,                                                   Morph,  true,  0,          Transform, true),
    f("slide",    Shape, ALL,                                                   Morph,  true,  0,          Transform, true),
    f("zoom",     Shape, ALL,                                                   Morph,  false, 0,          Transform, true),
    f("fade",     Shape, ALL,                                                   Morph,  false, 0,          Transform, true),
    f("flip",     Shape, ALL,                                                   Morph,  false, VESTIBULAR, Transform, true),
    f("bleed",    Shape, ALL,                                                   Morph,  false, 0,          Layer,     true),
    f("stepped",  Shape, ALL,                                                   Morph,  false, 0,          Transform, true),
    f("rubber",   Shape, ALL,                                                   Morph,  true,  0,          Transform, true),
    // W59.3: shape forms; W59.9a: on the peek, toasts, sidebars and dock; S21 (the user: "all animations for all
    // components"): every form but liquid serves every class — the dock, the bar's reveal and the web dock host them too.
    // iris, stamp and outline draw through a mask layer while they move.
    f("expand",   Shape, ALL,                                                   Morph,  false, 0,          Transform, true),
    f("iris",     Shape, ALL,                                                   Morph,  false, 0,          Layer,     true),
    f("stamp",    Shape, ALL,                                                   Morph,  true,  0,          Layer,     true),
    f("outline",  Shape, ALL,                                                   Morph,  false, 0,          Layer,     true),
    // W59.4: paper.
    f("fold",     Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh, true),
    f("book",     Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh,      true),
    f("roll",     Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh, true),
    f("crumple",  Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh,      true),
    // W59.5. (drop is a sheet form: its ripple refracts the captured card, CONTRACT-CHANGE row 670.)
    f("genie",    Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh,  true),
    f("crt",      Sheet, ALL,                                                   Finish, false, FLASH,      Layer,     true),
    f("drop",     Sheet, ALL,                                                   Finish, false, 0,          Layer,     true),
    f("liquid",   Shape, MORPHS,                                                Morph,  true,  0,          Transform, true),
    // W59.8: wave 3.
    f("fan",      Sheet, ALL,                                                   Finish, false, VESTIBULAR, Mesh,      true),
    f("noren",    Sheet, ALL,                                                   Finish, false, 0,          Mesh,      true),
    f("pixelate", Sheet, ALL,                                                   Finish, false, 0,          Layer,     true),
    f("glitch",   Sheet, ALL,                                                   Finish, false, FLASH,      Layer,     true),
    f("dissolve", Sheet, ALL,                                                   Finish, false, 0,          Layer,     true),
];

/// The form with this id.
pub fn form(id: &str) -> Option<&'static FormMeta> {
    FORMS.iter().find(|m| m.id == id)
}

/// The forms before K83 — what `motion.style` (the legacy token, Entrance) can name.
pub const LEGACY: [&str; 9] = [
    "none", "grow", "slide", "zoom", "fade", "flip", "bleed", "stepped", "rubber",
];

impl FormMeta {
    /// How much longer than the profile's curve this form runs (S21, the user: "raindrop or origami animate too fast to
    /// notice"). A factor on the curve's duration, so the speed setting and the user's own durations still scale it; the
    /// frontend's form Driver stretches the curve by it and Settings shows the stretched time. A sheet form tells a small
    /// story (a fold per panel, a bead that gathers, falls and spreads) that a 240 ms slide curve crosses in a few frames.
    pub fn pace(&self) -> f64 {
        match self.id {
            "drop" => 1.9,
            "genie" | "noren" => 1.5,
            "fold" | "book" | "fan" | "crumple" => 1.4,
            "roll" | "dissolve" => 1.3,
            "pixelate" | "iris" => 1.2,
            "crt" | "glitch" | "outline" | "stamp" => 1.1,
            _ => 1.0,
        }
    }
    /// Whether it may serve this surface class.
    pub fn serves(&self, surface: &str) -> bool {
        SURFACES
            .iter()
            .position(|s| *s == surface)
            .is_some_and(|i| self.surfaces & (1 << i) != 0)
    }
    pub fn surfaces(&self) -> impl Iterator<Item = &'static str> + '_ {
        SURFACES
            .iter()
            .enumerate()
            .filter(|(i, _)| self.surfaces & (1 << i) != 0)
            .map(|(_, s)| *s)
    }
    pub fn vestibular(&self) -> bool {
        self.flags & VESTIBULAR != 0
    }
    pub fn flash(&self) -> bool {
        self.flags & FLASH != 0
    }

    /// Its entry in the `motion.forms` meta token.
    pub fn json(&self) -> Value {
        let mut flags = vec![];
        if self.vestibular() {
            flags.push("vestibular");
        }
        if self.flash() {
            flags.push("flash");
        }
        json!({
            "family": match self.family { Shape => "shape", Sheet => "sheet" },
            "surfaces": self.surfaces().collect::<Vec<_>>(),
            "retarget": match self.retarget { Morph => "morph", Finish => "finish" },
            "overshoot": self.overshoot,
            "flags": flags,
            "tier": match self.tier { Transform => "transform", Layer => "layer", Mesh => "mesh" },
            "available": self.available,
            "pace": self.pace(),
        })
    }
}

/// The `motion.forms` meta token: every form, available or not.
pub fn meta() -> Value {
    Value::Object(FORMS.iter().map(|m| (m.id.to_owned(), m.json())).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_and_every_form_serves_the_island() {
        let mut ids: Vec<_> = FORMS.iter().map(|m| m.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), FORMS.len());
        for m in FORMS {
            assert!(m.serves("island"), "{} must serve the island (D3)", m.id);
            assert!(crate::curve::is_ident(m.id));
        }
    }

    #[test]
    fn surface_masks_name_the_right_classes() {
        for (i, name) in SURFACES.iter().enumerate() {
            assert_eq!(s(name), 1 << i, "{name}");
        }
        assert!(form("fold").unwrap().serves("peek"));
        assert!(form("fold").unwrap().serves("bar"));
        assert!(!form("liquid").unwrap().serves("bar"));
        assert!(form("roll").unwrap().serves("bar"));
        assert!(!form("grow").unwrap().serves("nowhere"));
    }

    #[test]
    fn every_form_is_available_where_it_is_drawn() {
        for id in LEGACY {
            assert!(form(id).unwrap().available, "{id}");
        }
        for id in ["fan", "noren", "fold", "pixelate", "glitch", "dissolve"] {
            assert!(form(id).unwrap().available, "{id}");
        }
        // W59.9a: the last one (liquid) has landed; the shape forms reach the peek, toasts, sidebars and dock.
        assert!(FORMS.iter().all(|m| m.available));
        assert!(form("iris").unwrap().serves("toast"));
        assert!(form("expand").unwrap().serves("dock"));
        // S21: every form but liquid on every class.
        assert!(FORMS.iter().filter(|m| m.id != "liquid").all(|m| m.surfaces().count() == 12));
        assert!(form("liquid").unwrap().serves("peek"));
        assert!(!form("liquid").unwrap().serves("sidebar"));
        let m = meta();
        assert_eq!(m["fold"]["family"], "sheet");
        assert_eq!(m["fold"]["flags"], json!(["vestibular"]));
        assert_eq!(m["crt"]["flags"], json!(["flash"]));
        assert_eq!(m["grow"]["available"], true);
        assert_eq!(m["grow"]["pace"], 1.0);
        assert!(m["drop"]["pace"].as_f64().unwrap() > m["fold"]["pace"].as_f64().unwrap());
        assert_eq!(m["grow"]["surfaces"].as_array().unwrap().len(), 12);
    }
}
