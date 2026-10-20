//! The LRC parser: `[mm:ss.xx]text` lines, as LRCLIB's `syncedLyrics` has them. Taken from shellseikatsu
//! (`Services/LyricsService.qml` `_parseLrc`: several stamps per line, one entry per stamp, sorted) and made strict where
//! it guessed: a fraction of 1 to 3 digits is that many tenths, hundredths or thousandths (shellseikatsu cut it to
//! hundredths), `[offset:±ms]` shifts every line (positive = earlier, as the LRC convention and LyricsX have it), metadata
//! tags (`[ar:…]`, `[ti:…]`, `[length:…]`) are skipped, enhanced word stamps (`<mm:ss.xx>`) are dropped from the text, and
//! a line whose stamp does not parse is skipped rather than guessed.

/// One synced line: its start in ms from the track's start, and its text (empty = a pause).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Line {
    pub t_ms: u64,
    pub text: String,
}

/// The lines of an LRC text, sorted by time (lines with the same time keep their order). Lines without a valid stamp
/// are skipped; an LRC with none gives no lines.
pub fn parse(lrc: &str) -> Vec<Line> {
    let mut offset: i64 = 0;
    let mut out: Vec<Line> = Vec::new();
    for raw in lrc.lines() {
        let raw = raw.trim_start_matches('\u{feff}').trim();
        let mut rest = raw;
        let mut stamps: Vec<u64> = Vec::new();
        let mut malformed = false;
        while let Some(body) = rest.strip_prefix('[') {
            let Some(end) = body.find(']') else {
                malformed = true;
                break;
            };
            let tag = &body[..end];
            rest = &body[end + 1..];
            match stamp(tag) {
                Some(ms) => stamps.push(ms),
                None => {
                    if let Some(v) = tag.strip_prefix("offset:") {
                        if let Ok(ms) = v.trim().trim_start_matches('+').parse::<i64>() {
                            offset = ms;
                        }
                    } else if !is_meta(tag) {
                        malformed = true;
                    }
                    if stamps.is_empty() {
                        // A metadata line (or a broken tag before any stamp): nothing to show.
                        break;
                    }
                }
            }
        }
        if malformed || stamps.is_empty() {
            continue;
        }
        let text = strip_word_stamps(rest).trim().to_string();
        for t in stamps {
            out.push(Line {
                t_ms: t,
                text: text.clone(),
            });
        }
    }
    for l in &mut out {
        l.t_ms = shift(l.t_ms, offset);
    }
    out.sort_by_key(|l| l.t_ms);
    out
}

/// `t` with the LRC offset applied: a positive offset makes lines come earlier; never before 0.
fn shift(t: u64, offset: i64) -> u64 {
    let t = i64::try_from(t).unwrap_or(i64::MAX);
    u64::try_from(t.saturating_sub(offset).max(0)).unwrap_or(0)
}

/// `mm:ss`, `mm:ss.f`, `mm:ss.ff`, `mm:ss.fff` (also `mm:ss:ff`, which some files use) → ms. Minutes may be any number
/// of digits; seconds are 0..59.
pub fn stamp(tag: &str) -> Option<u64> {
    let (min, rest) = tag.split_once(':')?;
    if min.is_empty() || !min.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let (sec, frac) = match rest.find(['.', ':']) {
        Some(i) => (&rest[..i], Some(&rest[i + 1..])),
        None => (rest, None),
    };
    if sec.len() != 2 || !sec.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let s: u64 = sec.parse().ok()?;
    if s >= 60 {
        return None;
    }
    let ms = match frac {
        None => 0,
        Some(f) if (1..=3).contains(&f.len()) && f.bytes().all(|b| b.is_ascii_digit()) => {
            let v: u64 = f.parse().ok()?;
            v * 10u64.pow(3 - u32::try_from(f.len()).ok()?)
        }
        Some(_) => return None,
    };
    let m: u64 = min.parse().ok()?;
    m.checked_mul(60_000)?.checked_add(s * 1000 + ms)
}

/// A metadata tag (`[ar:Artist]`, `[length: 3:20]`, `[re:…]`, `[#:comment]`): a short alphabetic id and a colon.
fn is_meta(tag: &str) -> bool {
    match tag.split_once(':') {
        Some((id, _)) => {
            !id.is_empty()
                && id.len() <= 8
                && id.chars().all(|c| c.is_ascii_alphabetic() || c == '#')
        }
        None => false,
    }
}

/// Removes enhanced-LRC word stamps (`<00:12.34>`) from a line's text.
fn strip_word_stamps(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(i) = rest.find('<') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        match after.find('>') {
            Some(j) if stamp(&after[..j]).is_some() => rest = &after[j + 1..],
            _ => {
                out.push('<');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    // Word stamps leave double spaces where they sat between words.
    let mut squeezed = String::with_capacity(out.len());
    let mut space = false;
    for c in out.chars() {
        if c == ' ' {
            if !space {
                squeezed.push(c);
            }
            space = true;
        } else {
            squeezed.push(c);
            space = false;
        }
    }
    squeezed
}

#[cfg(test)]
mod tests {
    use super::*;

    fn l(t_ms: u64, text: &str) -> Line {
        Line {
            t_ms,
            text: text.into(),
        }
    }

    #[test]
    fn stamps_take_one_to_three_fraction_digits() {
        assert_eq!(stamp("00:12"), Some(12_000));
        assert_eq!(stamp("00:12.5"), Some(12_500));
        assert_eq!(stamp("00:12.05"), Some(12_050));
        assert_eq!(stamp("01:02.345"), Some(62_345));
        assert_eq!(stamp("01:02:34"), Some(62_340));
        assert_eq!(stamp("123:00.00"), Some(7_380_000));
        assert_eq!(stamp("00:60.00"), None);
        assert_eq!(stamp("0:5.00"), None);
        assert_eq!(stamp("aa:12.00"), None);
        assert_eq!(stamp("00:12.1234"), None);
        assert_eq!(stamp("00:12."), None);
        assert_eq!(stamp("ar:Someone"), None);
    }

    #[test]
    fn lines_are_parsed_and_sorted() {
        let lrc = "[ar:Artist]\n[ti:Title]\n[00:05.00]second\n[00:01.50]first\n";
        assert_eq!(parse(lrc), vec![l(1_500, "first"), l(5_000, "second")]);
    }

    #[test]
    fn several_stamps_give_one_line_each() {
        let lrc = "[00:10.00][00:40.00]chorus\n[00:20.00]verse\n";
        assert_eq!(
            parse(lrc),
            vec![l(10_000, "chorus"), l(20_000, "verse"), l(40_000, "chorus")]
        );
    }

    #[test]
    fn the_offset_moves_every_line_and_never_below_zero() {
        let lrc = "[offset:+500]\n[00:00.20]a\n[00:02.00]b\n";
        assert_eq!(parse(lrc), vec![l(0, "a"), l(1_500, "b")]);
        let later = "[offset:-250]\n[00:01.00]a\n";
        assert_eq!(parse(later), vec![l(1_250, "a")]);
        // The tag applies wherever it stands in the file.
        let after = "[00:01.00]a\n[offset:1000]\n";
        assert_eq!(parse(after), vec![l(0, "a")]);
    }

    #[test]
    fn malformed_lines_are_skipped() {
        let lrc =
            "no stamp here\n[00:1x.00]broken\n[00:03.00\n[xx]text\n[00:04.00]kept\n\n[00:05.00]\n";
        assert_eq!(parse(lrc), vec![l(4_000, "kept"), l(5_000, "")]);
    }

    #[test]
    fn crlf_bom_and_word_stamps_are_cleaned() {
        let lrc = "\u{feff}[00:01.00]<00:01.00>Hello <00:01.50>world\r\n[00:02.00]  a <b> c  \r\n";
        assert_eq!(
            parse(lrc),
            vec![l(1_000, "Hello world"), l(2_000, "a <b> c")]
        );
    }

    #[test]
    fn unicode_text_is_kept() {
        assert_eq!(parse("[00:07.12]夜に駆ける"), vec![l(7_120, "夜に駆ける")]);
    }

    #[test]
    fn nothing_parses_from_plain_text() {
        assert!(parse("just words\nmore words").is_empty());
        assert!(parse("").is_empty());
    }
}
