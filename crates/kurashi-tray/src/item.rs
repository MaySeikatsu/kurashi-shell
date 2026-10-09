//! One StatusNotifierItem: read its properties in one call and turn its icon into a PNG.

use std::collections::HashMap;
use std::io::Cursor;

use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

use crate::{CALL_TIMEOUT, ITEM_IFACE};

/// `a(iiay)`: width, height, then ARGB32 pixels in network byte order.
pub type Pixmap = (i32, i32, Vec<u8>);
/// `(sa(iiay)ss)`: icon name, icon pixmaps, title, description.
type ToolTip = (String, Vec<Pixmap>, String, String);

/// Icons up to this size are shipped; bigger ones only when nothing smaller exists. Every size
/// in every patch would bloat the document.
const ICON_MAX: i32 = 48;

/// What the document needs from one item.
#[derive(Clone, Debug)]
pub struct View {
    pub title: String,
    pub status: String,
    pub icon_name: String,
    pub icon: Option<Icon>,
    pub tooltip: Option<String>,
    /// Object path of the item's dbusmenu, when it has one.
    pub menu: Option<String>,
}

#[derive(Clone, Debug)]
pub struct Icon {
    pub w: i32,
    pub h: i32,
    pub png_base64: String,
}

/// Read all of the item's properties in one call. `None` when it does not answer.
pub async fn read(conn: &Connection, unique: &str, path: &str) -> Option<View> {
    let props = get_all(conn, unique, path, ITEM_IFACE).await?;
    let status = prop::<String>(&props, "Status").unwrap_or_else(|| "Active".into());
    // NeedsAttention swaps in the attention icon, but only when the item actually provides one.
    let attention_name = prop::<String>(&props, "AttentionIconName").unwrap_or_default();
    let attention_pixmaps = prop::<Vec<Pixmap>>(&props, "AttentionIconPixmap").unwrap_or_default();
    let (icon_name, pixmaps) = if status == "NeedsAttention"
        && (!attention_name.is_empty() || !attention_pixmaps.is_empty())
    {
        (attention_name, attention_pixmaps)
    } else {
        (
            prop::<String>(&props, "IconName").unwrap_or_default(),
            prop::<Vec<Pixmap>>(&props, "IconPixmap").unwrap_or_default(),
        )
    };
    Some(View {
        title: prop::<String>(&props, "Title").unwrap_or_default(),
        status,
        icon_name,
        icon: best_icon(&pixmaps),
        tooltip: prop::<ToolTip>(&props, "ToolTip")
            .and_then(|(_, _, title, text)| tooltip(title, text)),
        menu: prop::<OwnedObjectPath>(&props, "Menu")
            .map(|p| p.to_string())
            .filter(|p| !p.is_empty() && p != "/"),
    })
}

fn tooltip(title: String, text: String) -> Option<String> {
    let parts: Vec<String> = [title, text]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect();
    (!parts.is_empty()).then(|| parts.join("\n"))
}

/// The largest pixmap that fits [`ICON_MAX`], else the smallest one, as PNG.
fn best_icon(pixmaps: &[Pixmap]) -> Option<Icon> {
    let usable = |p: &&Pixmap| {
        let (w, h, px) = p;
        *w > 0
            && *h > 0
            && (*w as u64)
                .checked_mul(*h as u64)
                .and_then(|a| a.checked_mul(4))
                == Some(px.len() as u64)
    };
    let area = |p: &&Pixmap| i64::from(p.0) * i64::from(p.1);
    let pick = pixmaps
        .iter()
        .filter(usable)
        .filter(|p| p.0 <= ICON_MAX && p.1 <= ICON_MAX)
        .max_by_key(area)
        .or_else(|| pixmaps.iter().filter(usable).min_by_key(area))?;
    let (w, h, argb) = pick;
    // Wire order is ARGB; PNG wants RGBA.
    let rgba: Vec<u8> = argb
        .chunks_exact(4)
        .flat_map(|p| [p[1], p[2], p[3], p[0]])
        .collect();
    let img = image::RgbaImage::from_raw(*w as u32, *h as u32, rgba)?;
    let mut png = Vec::new();
    image::DynamicImage::ImageRgba8(img)
        .write_to(Cursor::new(&mut png), image::ImageFormat::Png)
        .ok()?;
    Some(Icon {
        w: *w,
        h: *h,
        png_base64: base64(&png),
    })
}

/// Standard alphabet with padding. Hand-rolled: one call site does not justify a new dependency.
pub fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |acc, (i, b)| acc | u32::from(*b) << (16 - 8 * i));
        for i in 0..4usize {
            if i <= chunk.len() {
                out.push(char::from(ALPHABET[(n >> (18 - 6 * i)) as usize & 63]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// `GetAll` on one interface, bounded by [`CALL_TIMEOUT`].
pub async fn get_all(
    conn: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
) -> Option<HashMap<String, OwnedValue>> {
    let proxy = zbus::fdo::PropertiesProxy::builder(conn)
        .destination(dest.to_owned())
        .ok()?
        .path(path.to_owned())
        .ok()?
        .build()
        .await
        .ok()?;
    let iface = zbus::names::InterfaceName::try_from(iface.to_owned()).ok()?;
    tokio::time::timeout(CALL_TIMEOUT, proxy.get_all(iface))
        .await
        .ok()?
        .ok()
}

pub fn prop<T: TryFrom<OwnedValue>>(props: &HashMap<String, OwnedValue>, key: &str) -> Option<T> {
    props.get(key)?.try_clone().ok()?.try_into().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_rfc4648_vectors() {
        let cases = [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy"),
        ];
        for (plain, encoded) in cases {
            assert_eq!(base64(plain.as_bytes()), encoded, "input {plain:?}");
        }
    }

    #[test]
    fn icon_is_png_from_argb_and_prefers_the_largest_small_size() {
        // 1x1 red, opaque, ARGB network order.
        let red = vec![255, 255, 0, 0];
        let icon = best_icon(&[(1, 1, red)]).expect("valid 1x1 pixmap");
        assert_eq!((icon.w, icon.h), (1, 1));
        assert!(icon.png_base64.starts_with("iVBORw0KGgo"), "PNG signature");

        let big = (100, 100, vec![0; 100 * 100 * 4]);
        let small = (16, 16, vec![0; 16 * 16 * 4]);
        let mid = (32, 32, vec![0; 32 * 32 * 4]);
        let picked = best_icon(&[big, small, mid]).expect("a pixmap fits");
        assert_eq!((picked.w, picked.h), (32, 32));
    }

    #[test]
    fn malformed_pixmaps_are_skipped() {
        assert!(best_icon(&[(2, 2, vec![0; 3])]).is_none());
        assert!(best_icon(&[(0, 4, vec![])]).is_none());
        assert!(best_icon(&[]).is_none());
    }
}
