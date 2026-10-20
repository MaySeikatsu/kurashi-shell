//! Inline calculator for the launcher's query (Capsule's launcher, session 9): `2^8`, `15% of 2500`,
//! `sqrt(2)*pi`, `(3+4)/2`. A query that is not arithmetic, or has no operator or function at all (a
//! bare number), is not a calculation: apps keep the list. Unit conversions (Capsule, I105):
//! `10 km to mi`, `72 f in c`, `1.5 GiB to MB`, `3h to min`.

/// The value of `q` when it is a calculation, else `None`.
pub fn eval(q: &str) -> Option<f64> {
    let q = q.trim().trim_end_matches('=').trim();
    if q.is_empty() {
        return None;
    }
    let lower = q.to_ascii_lowercase();
    // "15% of 2500"
    if let Some((a, b)) = lower.split_once("% of ") {
        let (a, b) = (eval_expr(a)?, eval_expr(b)?);
        return Some(a / 100.0 * b);
    }
    // An operator past the first character: a leading minus alone ("-5") is a number.
    let has_op = lower.chars().skip(1).any(|c| "+-*/^%(×÷".contains(c));
    let has_fn = FUNCS.iter().any(|f| lower.contains(f));
    if !has_op && !has_fn {
        return None;
    }
    let v = eval_expr(&lower)?;
    v.is_finite().then_some(v)
}

/// `v` as the launcher shows it: integers plainly, others with up to 10 significant decimals.
pub fn format(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e15 {
        return format!("{}", v as i64);
    }
    let s = format!("{v:.10}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

const FUNCS: [&str; 9] = [
    "sqrt", "sin", "cos", "tan", "ln", "log", "abs", "pi", "round",
];

fn eval_expr(s: &str) -> Option<f64> {
    let toks: Vec<char> = s
        .chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| match c {
            '×' => '*',
            '÷' => '/',
            ',' => '.',
            c => c,
        })
        .collect();
    let mut p = Parser { t: &toks, i: 0 };
    let v = p.sum()?;
    (p.i == toks.len()).then_some(v)
}

struct Parser<'a> {
    t: &'a [char],
    i: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<char> {
        self.t.get(self.i).copied()
    }
    fn eat(&mut self, c: char) -> bool {
        let hit = self.peek() == Some(c);
        if hit {
            self.i += 1;
        }
        hit
    }
    fn sum(&mut self) -> Option<f64> {
        let mut v = self.product()?;
        loop {
            if self.eat('+') {
                v += self.product()?;
            } else if self.eat('-') {
                v -= self.product()?;
            } else {
                return Some(v);
            }
        }
    }
    fn product(&mut self) -> Option<f64> {
        let mut v = self.power()?;
        loop {
            if self.eat('*') {
                v *= self.power()?;
            } else if self.eat('/') {
                v /= self.power()?;
            } else if self.eat('%') {
                // `a % b` is the remainder; a trailing `%` is percent.
                if matches!(self.peek(), None | Some(')' | '+' | '-' | '*' | '/')) {
                    v /= 100.0;
                } else {
                    v %= self.power()?;
                }
            } else {
                return Some(v);
            }
        }
    }
    fn power(&mut self) -> Option<f64> {
        let base = self.unary()?;
        if self.eat('^') {
            return Some(base.powf(self.power()?));
        }
        Some(base)
    }
    fn unary(&mut self) -> Option<f64> {
        if self.eat('-') {
            return Some(-self.unary()?);
        }
        if self.eat('+') {
            return self.unary();
        }
        self.atom()
    }
    fn atom(&mut self) -> Option<f64> {
        if self.eat('(') {
            let v = self.sum()?;
            return self.eat(')').then_some(v);
        }
        let start = self.i;
        if self.peek().is_some_and(|c| c.is_ascii_alphabetic()) {
            while self.peek().is_some_and(|c| c.is_ascii_alphabetic()) {
                self.i += 1;
            }
            let name: String = self.t[start..self.i].iter().collect();
            return match name.as_str() {
                "pi" => Some(std::f64::consts::PI),
                "e" => Some(std::f64::consts::E),
                f => {
                    let x = self.atom()?;
                    match f {
                        "sqrt" => Some(x.sqrt()),
                        "sin" => Some(x.to_radians().sin()),
                        "cos" => Some(x.to_radians().cos()),
                        "tan" => Some(x.to_radians().tan()),
                        "ln" => Some(x.ln()),
                        "log" => Some(x.log10()),
                        "abs" => Some(x.abs()),
                        "round" => Some(x.round()),
                        _ => None,
                    }
                }
            };
        }
        while self.peek().is_some_and(|c| c.is_ascii_digit() || c == '.') {
            self.i += 1;
        }
        if start == self.i {
            return None;
        }
        self.t[start..self.i]
            .iter()
            .collect::<String>()
            .parse()
            .ok()
    }
}

/// Kinds of quantity a conversion stays within.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Dim {
    Length,
    Mass,
    Volume,
    Time,
    Data,
    Speed,
    Temp,
}

/// Unit names (lower case; the first name is how a result is shown) and their factor to the base unit
/// of their kind. Temperatures convert through `temp_*` instead.
const UNITS: &[(&[&str], Dim, f64)] = &[
    (
        &["m", "meter", "meters", "metre", "metres"],
        Dim::Length,
        1.0,
    ),
    (&["km", "kilometer", "kilometers"], Dim::Length, 1000.0),
    (&["cm"], Dim::Length, 0.01),
    (&["mm"], Dim::Length, 0.001),
    (&["mi", "mile", "miles"], Dim::Length, 1609.344),
    (&["yd", "yard", "yards"], Dim::Length, 0.9144),
    (&["ft", "foot", "feet"], Dim::Length, 0.3048),
    (&["in", "inch", "inches"], Dim::Length, 0.0254),
    (&["nmi"], Dim::Length, 1852.0),
    (&["kg", "kilo", "kilos"], Dim::Mass, 1.0),
    (&["g", "gram", "grams"], Dim::Mass, 0.001),
    (&["mg"], Dim::Mass, 1e-6),
    (&["t", "tonne", "tonnes"], Dim::Mass, 1000.0),
    (&["lb", "lbs", "pound", "pounds"], Dim::Mass, 0.453_592_37),
    (&["oz", "ounce", "ounces"], Dim::Mass, 0.028_349_523_125),
    (
        &["l", "liter", "liters", "litre", "litres"],
        Dim::Volume,
        1.0,
    ),
    (&["ml"], Dim::Volume, 0.001),
    (&["gal", "gallon", "gallons"], Dim::Volume, 3.785_411_784),
    (&["cup", "cups"], Dim::Volume, 0.236_588_236_5),
    (&["s", "sec", "secs", "second", "seconds"], Dim::Time, 1.0),
    (&["ms"], Dim::Time, 0.001),
    (&["min", "mins", "minute", "minutes"], Dim::Time, 60.0),
    (&["h", "hr", "hrs", "hour", "hours"], Dim::Time, 3600.0),
    (&["d", "day", "days"], Dim::Time, 86400.0),
    (&["wk", "week", "weeks"], Dim::Time, 604_800.0),
    (&["b", "byte", "bytes"], Dim::Data, 1.0),
    (&["kb"], Dim::Data, 1e3),
    (&["mb"], Dim::Data, 1e6),
    (&["gb"], Dim::Data, 1e9),
    (&["tb"], Dim::Data, 1e12),
    (&["kib"], Dim::Data, 1024.0),
    (&["mib"], Dim::Data, 1_048_576.0),
    (&["gib"], Dim::Data, 1_073_741_824.0),
    (&["tib"], Dim::Data, 1_099_511_627_776.0),
    (&["m/s"], Dim::Speed, 1.0),
    (&["km/h", "kmh", "kph"], Dim::Speed, 1.0 / 3.6),
    (&["mph"], Dim::Speed, 0.44704),
    (&["kn", "knot", "knots"], Dim::Speed, 0.514_444),
    (&["c", "°c", "celsius"], Dim::Temp, 0.0),
    (&["f", "°f", "fahrenheit"], Dim::Temp, 1.0),
    (&["k", "kelvin"], Dim::Temp, 2.0),
];

fn unit(name: &str) -> Option<(&'static str, Dim, f64)> {
    let n = name.trim();
    // Data units keep their case meaning loosely (MB = megabyte); everything else is lower case.
    let lower = n.to_lowercase();
    UNITS
        .iter()
        .find(|(names, _, _)| names.contains(&lower.as_str()))
        .map(|(names, d, f)| (names[0], *d, *f))
}

fn to_celsius(v: f64, which: f64) -> f64 {
    match which as i32 {
        1 => (v - 32.0) * 5.0 / 9.0,
        2 => v - 273.15,
        _ => v,
    }
}

fn from_celsius(c: f64, which: f64) -> f64 {
    match which as i32 {
        1 => c * 9.0 / 5.0 + 32.0,
        2 => c + 273.15,
        _ => c,
    }
}

/// `q` as a unit conversion — `<amount> <unit> to|in|-> <unit>` — the converted value and the target
/// unit's name as shown (`"mi"`, `"°F"`…); `None` for anything else or units of different kinds.
pub fn convert(q: &str) -> Option<(f64, String)> {
    let lower = q.trim().to_lowercase();
    let (lhs, target) = [" to ", " in ", " -> ", " → ", " as "]
        .iter()
        .find_map(|sep| lower.split_once(sep))?;
    let lhs = lhs.trim();
    // Split the amount from its unit: the unit is the trailing run of letters, `/`, `°`.
    let cut = lhs
        .char_indices()
        .rev()
        .take_while(|(_, c)| c.is_alphabetic() || *c == '/' || *c == '°')
        .last()
        .map(|(i, _)| i)?;
    let (amount, from) = lhs.split_at(cut);
    let amount = amount.trim();
    let v = amount.parse::<f64>().ok().or_else(|| eval_expr(amount))?;
    let (_, fd, ff) = unit(from)?;
    let (tname, td, tf) = unit(target)?;
    if fd != td {
        return None;
    }
    let out = if fd == Dim::Temp {
        from_celsius(to_celsius(v, ff), tf)
    } else {
        v * ff / tf
    };
    let shown = match tname {
        "c" => "°C".to_owned(),
        "f" => "°F".to_owned(),
        "k" => "K".to_owned(),
        "kb" | "mb" | "gb" | "tb" => tname.to_uppercase(),
        "kib" | "mib" | "gib" | "tib" => format!("{}iB", tname[..1].to_uppercase()),
        "b" => "B".to_owned(),
        other => other.to_owned(),
    };
    out.is_finite().then_some((out, shown))
}

/// `v` rounded for a conversion row: up to 4 decimals, more only for tiny values.
pub fn format_unit(v: f64) -> String {
    if v != 0.0 && v.abs() < 0.001 {
        return format!("{v:.3e}");
    }
    let s = format!("{v:.4}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arithmetic_and_functions() {
        assert_eq!(eval("2^8"), Some(256.0));
        assert_eq!(eval("(3+4)/2"), Some(3.5));
        assert_eq!(eval("15% of 2500"), Some(375.0));
        assert_eq!(eval("2 * -3"), Some(-6.0));
        assert_eq!(eval("10 % 3"), Some(1.0));
        assert_eq!(eval("50%"), Some(0.5));
        assert!((eval("sqrt(2)").unwrap() - std::f64::consts::SQRT_2).abs() < 1e-12);
        assert_eq!(format(eval("sin(30)").unwrap()), "0.5");
        assert_eq!(eval("3×4"), Some(12.0));
    }

    #[test]
    fn apps_and_numbers_are_not_calculations() {
        assert_eq!(eval("firefox"), None);
        assert_eq!(eval("42"), None);
        assert_eq!(eval("-5"), None);
        assert_eq!(eval("2+"), None);
        assert_eq!(eval("1/0"), None);
        assert_eq!(eval(""), None);
        assert_eq!(eval("gimp-2.10"), None);
    }

    #[test]
    fn formatting() {
        assert_eq!(format(256.0), "256");
        assert_eq!(format(1.0 / 3.0), "0.3333333333");
        assert_eq!(format(-2.5), "-2.5");
    }

    #[test]
    fn unit_conversions() {
        let c = |q: &str| convert(q).map(|(v, u)| format!("{} {u}", format_unit(v)));
        assert_eq!(c("10 km to mi").as_deref(), Some("6.2137 mi"));
        assert_eq!(c("72 f in c").as_deref(), Some("22.2222 °C"));
        assert_eq!(c("100c to f").as_deref(), Some("212 °F"));
        assert_eq!(c("1.5 GiB to MB").as_deref(), Some("1610.6127 MB"));
        assert_eq!(c("3h to min").as_deref(), Some("180 min"));
        assert_eq!(c("5 kg in lb").as_deref(), Some("11.0231 lb"));
        assert_eq!(c("100 km/h to mph").as_deref(), Some("62.1371 mph"));
        assert_eq!(c("2*3 m to ft").as_deref(), Some("19.685 ft"));
        assert_eq!(c("5 kg to m"), None);
        assert_eq!(c("open to do"), None);
        assert_eq!(c("firefox"), None);
    }
}
