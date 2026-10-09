//! Body-markup sanitiser. Spec 1.2 allows b/i/u/a/img; we keep b, i, u and `a` with a
//! http(s)/mailto href only. Everything else is dropped (script/style with their content), so the
//! frontend can render the result without trusting the sender (Shōjiki: show only what is safe).

const KEEP: [&str; 4] = ["b", "i", "u", "a"];
const DROP_WITH_CONTENT: [&str; 2] = ["script", "style"];

pub fn sanitize(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    // Indices into KEEP, innermost last, plus how many of each are open. The counts make an
    // unmatched closing tag O(1); scanning the stack for one was quadratic on "<b>…</i>…".
    let mut open: Vec<usize> = Vec::new();
    let mut depth = [0usize; KEEP.len()];
    let mut rest = input;
    while let Some(lt) = rest.find('<') {
        out.push_str(&rest[..lt]);
        let after = &rest[lt + 1..];
        let Some(gt) = after.find('>') else {
            // No '>' after this point, so nothing from here on can be a tag: the rest is text.
            // Handling each '<' on its own rescanned the remainder every time (quadratic).
            out.push_str(&rest[lt..].replace('<', "&lt;"));
            rest = "";
            break;
        };
        let inner = &after[..gt];
        rest = &after[gt + 1..];
        let closing = inner.starts_with('/');
        let body = inner.trim_start_matches('/').trim_end_matches('/');
        let name_end = body.find(|c: char| c.is_whitespace()).unwrap_or(body.len());
        let name = body[..name_end].to_ascii_lowercase();
        if !closing && DROP_WITH_CONTENT.contains(&name.as_str()) {
            let needle = format!("</{name}");
            // Case-insensitive without copying `rest`: a lowercase copy per dropped element was
            // quadratic.
            rest = match find_ascii_ci(rest, &needle) {
                Some(p) => match rest[p..].find('>') {
                    Some(g) => &rest[p + g + 1..],
                    None => "",
                },
                None => "",
            };
            continue;
        }
        let Some(ki) = KEEP.iter().position(|k| *k == name) else {
            continue;
        };
        let tag = KEEP[ki];
        if closing {
            if depth[ki] > 0 {
                // Close anything opened inside it first so output stays well-nested.
                while let Some(t) = open.pop() {
                    depth[t] -= 1;
                    out.push_str(&format!("</{}>", KEEP[t]));
                    if t == ki {
                        break;
                    }
                }
            }
        } else if tag == "a" {
            if let Some(href) = href(&body[name_end..]) {
                out.push_str(&format!("<a href=\"{href}\">"));
                open.push(ki);
                depth[ki] += 1;
            }
        } else {
            out.push_str(&format!("<{tag}>"));
            open.push(ki);
            depth[ki] += 1;
        }
    }
    out.push_str(rest);
    while let Some(t) = open.pop() {
        out.push_str(&format!("</{}>", KEEP[t]));
    }
    out
}

/// ASCII case-insensitive `find` for an ASCII `needle`, without copying `hay`.
fn find_ascii_ci(hay: &str, needle: &str) -> Option<usize> {
    hay.as_bytes()
        .windows(needle.len())
        .position(|w| w.eq_ignore_ascii_case(needle.as_bytes()))
}

fn href(attrs: &str) -> Option<String> {
    let at = attrs.to_ascii_lowercase().find("href")?;
    let v = attrs[at + 4..].trim_start().strip_prefix('=')?.trim_start();
    let (q, v) = match v.chars().next()? {
        c @ ('"' | '\'') => (c, &v[1..]),
        _ => return None,
    };
    let url = &v[..v.find(q)?];
    let l = url.trim().to_ascii_lowercase();
    ["http://", "https://", "mailto:"]
        .iter()
        .any(|s| l.starts_with(s))
        .then(|| url.trim().replace('"', "&quot;").replace('<', "&lt;"))
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::sanitize;

    /// Budget for 1 MB of hostile markup: 100 ms release, 1 s debug.
    fn budget() -> Duration {
        if cfg!(debug_assertions) {
            Duration::from_secs(1)
        } else {
            Duration::from_millis(100)
        }
    }

    #[test]
    fn drop_blocks_are_linear() {
        let input = "<style>x</style>".repeat(1 << 16); // 1 MiB
        let t = Instant::now();
        let out = sanitize(&input);
        let took = t.elapsed();
        assert!(out.is_empty());
        assert!(took < budget(), "sanitize took {took:?}");
    }

    #[test]
    fn lone_lt_is_linear() {
        let input = "<".repeat(1 << 20);
        let t = Instant::now();
        let out = sanitize(&input);
        let took = t.elapsed();
        assert!(out == "&lt;".repeat(1 << 20));
        assert!(took < budget(), "sanitize took {took:?}");
    }

    #[test]
    fn unmatched_closers_are_linear() {
        let input = format!("{}{}", "<b>".repeat(1 << 16), "</i>".repeat(1 << 16));
        let t = Instant::now();
        let out = sanitize(&input);
        let took = t.elapsed();
        assert!(out == format!("{}{}", "<b>".repeat(1 << 16), "</b>".repeat(1 << 16)));
        assert!(took < budget(), "sanitize took {took:?}");
    }

    #[test]
    fn strips_dangerous() {
        assert_eq!(sanitize("a<script>alert(1)</script>b"), "ab");
        assert_eq!(sanitize("x<img src=\"file:///etc/passwd\"/>y"), "xy");
        assert_eq!(sanitize("<b>hi</b> <i>there"), "<b>hi</b> <i>there</i>");
        assert_eq!(
            sanitize("<a href=\"javascript:evil()\">x</a>"),
            "x",
            "bad scheme dropped"
        );
        assert_eq!(
            sanitize("<a href=\"https://e.org\">x</a>"),
            "<a href=\"https://e.org\">x</a>"
        );
        assert_eq!(sanitize("1 < 2"), "1 &lt; 2");
    }
}
