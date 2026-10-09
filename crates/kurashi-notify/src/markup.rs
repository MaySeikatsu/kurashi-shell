//! Body-markup sanitiser. Spec 1.2 allows b/i/u/a/img; we keep b, i, u and `a` with a
//! http(s)/mailto href only. Everything else is dropped (script/style with their content), so the
//! frontend can render the result without trusting the sender (Shōjiki: show only what is safe).

const KEEP: [&str; 4] = ["b", "i", "u", "a"];
const DROP_WITH_CONTENT: [&str; 2] = ["script", "style"];

pub fn sanitize(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut open: Vec<&'static str> = Vec::new();
    let mut rest = input;
    while let Some(lt) = rest.find('<') {
        out.push_str(&rest[..lt]);
        let after = &rest[lt + 1..];
        let Some(gt) = after.find('>') else {
            // Unterminated tag: literal text.
            out.push_str("&lt;");
            rest = after;
            continue;
        };
        let inner = &after[..gt];
        rest = &after[gt + 1..];
        let closing = inner.starts_with('/');
        let body = inner.trim_start_matches('/').trim_end_matches('/');
        let name_end = body.find(|c: char| c.is_whitespace()).unwrap_or(body.len());
        let name = body[..name_end].to_ascii_lowercase();
        if !closing && DROP_WITH_CONTENT.contains(&name.as_str()) {
            let needle = format!("</{name}");
            let lower = rest.to_ascii_lowercase();
            rest = match lower.find(&needle) {
                Some(p) => match rest[p..].find('>') {
                    Some(g) => &rest[p + g + 1..],
                    None => "",
                },
                None => "",
            };
            continue;
        }
        let Some(tag) = KEEP.iter().copied().find(|k| *k == name) else {
            continue;
        };
        if closing {
            if let Some(pos) = open.iter().rposition(|t| *t == tag) {
                // Close anything opened inside it first so output stays well-nested.
                while open.len() > pos {
                    let t = open.pop().unwrap();
                    out.push_str(&format!("</{t}>"));
                }
            }
        } else if tag == "a" {
            if let Some(href) = href(&body[name_end..]) {
                out.push_str(&format!("<a href=\"{href}\">"));
                open.push("a");
            }
        } else {
            out.push_str(&format!("<{tag}>"));
            open.push(tag);
        }
    }
    out.push_str(rest);
    while let Some(t) = open.pop() {
        out.push_str(&format!("</{t}>"));
    }
    out
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
    use super::sanitize;

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
