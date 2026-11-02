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
/// Every class but these.
const fn but(mask: u16) -> u16 {
    ALL & !mask
}
/// The cards that open from a bar or the island (a mesh needs room to fold, roll or pour).
const CARDS: u16 = s("island") | s("panel") | s("launcher") | s("centre") | s("dialog");

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
    f("none",     Shape, ALL,                                                  Morph,  false, 0,          Transform, true),
    f("grow",     Shape, ALL,                                                  Morph,  true,  0,          Transform, true),
    f("slide",    Shape, ALL,                                                  Morph,  true,  0,          Transform, true),
    f("zoom",     Shape, ALL,                                                  Morph,  false, 0,          Transform, true),
    f("fade",     Shape, ALL,                                                  Morph,  false, 0,          Transform, true),
    f("flip",     Shape, ALL,                                                  Morph,  false, VESTIBULAR, Transform, true),
    f("bleed",    Shape, ALL,                                                  Morph,  false, 0,          Layer,     true),
    f("stepped",  Shape, ALL,                                                  Morph,  false, 0,          Transform, true),
    f("rubber",   Shape, ALL,                                                  Morph,  true,  0,          Transform, true),
    // W59.3: shape forms.
    f("expand",   Shape, ALL,                                                  Morph,  false, 0,          Transform, false),
    f("iris",     Shape, but(s("bar")),                                        Morph,  false, 0,          Transform, false),
    f("stamp",    Shape, but(s("bar") | s("dock") | s("sidebar")),             Morph,  true,  0,          Transform, false),
    f("outline",  Shape, but(s("bar")),                                        Morph,  false, 0,          Transform, false),
    // W59.4: paper.
    f("fold",     Sheet, CARDS | s("peek") | s("toast") | s("sidebar") | s("menu"), Finish, false, VESTIBULAR, Mesh, true),
    f("book",     Sheet, CARDS,                                                Finish, false, VESTIBULAR, Mesh,      true),
    f("roll",     Sheet, CARDS | s("sidebar") | s("bar") | s("toast") | s("dock") | s("menu"), Finish, false, VESTIBULAR, Mesh, true),
    f("crumple",  Sheet, CARDS | s("toast") | s("peek"),                       Finish, false, VESTIBULAR, Mesh,      true),
    // W59.5. (drop is a sheet form: its ripple refracts the captured card, CONTRACT-CHANGE row 670.)
    f("genie",    Sheet, CARDS | s("dock") | s("toast") | s("peek") | s("menu"), Finish, false, VESTIBULAR, Mesh,  true),
    f("crt",      Sheet, ALL,                                                  Finish, false, FLASH,      Layer,     true),
    f("drop",     Sheet, CARDS | s("toast") | s("peek") | s("osd"),            Finish, false, 0,          Layer,     true),
    f("liquid",   Shape, but(s("bar") | s("dock")),                            Morph,  true,  0,          Transform, false),
    // W59.8: wave 3.
    f("fan",      Sheet, CARDS | s("peek") | s("menu"),                        Finish, false, VESTIBULAR, Mesh,      true),
    f("noren",    Sheet, CARDS | s("sidebar") | s("toast"),                    Finish, false, 0,          Mesh,      true),
    f("pixelate", Sheet, ALL,                                                  Finish, false, 0,          Layer,     false),
    f("glitch",   Sheet, ALL,                                                  Finish, false, FLASH,      Layer,     false),
    f("dissolve", Sheet, ALL,                                                  Finish, false, 0,          Layer,     false),
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
        assert!(!form("fold").unwrap().serves("bar"));
        assert!(!form("iris").unwrap().serves("bar"));
        assert!(form("roll").unwrap().serves("bar"));
        assert!(!form("grow").unwrap().serves("nowhere"));
    }

    #[test]
    fn todays_forms_are_available_and_the_new_ones_wait_for_their_cards() {
        for id in LEGACY {
            assert!(form(id).unwrap().available, "{id}");
        }
        for id in ["liquid", "fan", "glitch"] {
            assert!(!form(id).unwrap().available, "{id}");
        }
        let m = meta();
        assert_eq!(m["fold"]["family"], "sheet");
        assert_eq!(m["fold"]["flags"], json!(["vestibular"]));
        assert_eq!(m["crt"]["flags"], json!(["flash"]));
        assert_eq!(m["grow"]["available"], true);
        assert_eq!(m["grow"]["surfaces"].as_array().unwrap().len(), 12);
    }
}
