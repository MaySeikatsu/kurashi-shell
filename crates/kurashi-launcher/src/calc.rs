//! Inline calculator for the launcher's query (Capsule's launcher, session 9): `2^8`, `15% of 2500`,
//! `sqrt(2)*pi`, `(3+4)/2`. A query that is not arithmetic, or has no operator or function at all (a
//! bare number), is not a calculation: apps keep the list.

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

const FUNCS: [&str; 9] = ["sqrt", "sin", "cos", "tan", "ln", "log", "abs", "pi", "round"];

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
}
