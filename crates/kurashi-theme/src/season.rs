//! 旬 (Shun): the 24 solar terms (二十四節気) from a calendar date. No clock access here;
//! the caller passes the date so results are deterministic and testable.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Date {
    pub year: i32,
    pub month: u8,
    pub day: u8,
}

impl Date {
    pub fn new(year: i32, month: u8, day: u8) -> Date {
        Date { year, month, day }
    }

    pub fn day_of_year(self) -> u32 {
        const CUM: [u32; 12] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
        let leap = (self.year % 4 == 0 && self.year % 100 != 0) || self.year % 400 == 0;
        let m = usize::from(self.month.clamp(1, 12)) - 1;
        CUM[m] + u32::from(self.day) + u32::from(leap && m >= 2)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct SolarTerm {
    /// 0 = 小寒 .. 23 = 冬至, calendar order within a year.
    pub index: usize,
    pub ja: &'static str,
    pub romaji: &'static str,
    start: (u8, u8),
}

// Approximate start dates (they drift by +-1 day between years; fine for a colour nudge).
const TERMS: [SolarTerm; 24] = {
    const fn t(index: usize, ja: &'static str, romaji: &'static str, m: u8, d: u8) -> SolarTerm {
        SolarTerm {
            index,
            ja,
            romaji,
            start: (m, d),
        }
    }
    [
        t(0, "小寒", "shokan", 1, 6),
        t(1, "大寒", "daikan", 1, 20),
        t(2, "立春", "risshun", 2, 4),
        t(3, "雨水", "usui", 2, 19),
        t(4, "啓蟄", "keichitsu", 3, 6),
        t(5, "春分", "shunbun", 3, 21),
        t(6, "清明", "seimei", 4, 5),
        t(7, "穀雨", "kokuu", 4, 20),
        t(8, "立夏", "rikka", 5, 6),
        t(9, "小満", "shoman", 5, 21),
        t(10, "芒種", "boshu", 6, 6),
        t(11, "夏至", "geshi", 6, 21),
        t(12, "小暑", "shosho", 7, 7),
        t(13, "大暑", "taisho", 7, 23),
        t(14, "立秋", "risshu", 8, 8),
        t(15, "処暑", "shosho-heat", 8, 23),
        t(16, "白露", "hakuro", 9, 8),
        t(17, "秋分", "shubun", 9, 23),
        t(18, "寒露", "kanro", 10, 8),
        t(19, "霜降", "soko", 10, 23),
        t(20, "立冬", "ritto", 11, 7),
        t(21, "小雪", "shosetsu", 11, 22),
        t(22, "大雪", "taisetsu", 12, 7),
        t(23, "冬至", "toji", 12, 22),
    ]
};

pub fn solar_term(d: Date) -> SolarTerm {
    let key = (d.month, d.day);
    // Before 小寒 (Jan 1-5) we are still in 冬至.
    TERMS
        .iter()
        .rev()
        .find(|t| t.start <= key)
        .copied()
        .unwrap_or(TERMS[23])
}

/// The season a hue leans toward (I281: each season its own colour, not only warm and cold): the anchors, by the day
/// of the year a term starts, with hues unwrapped so the year runs winter blue → plum → sakura → rape-flower yellow →
/// fresh green → golden → maple → crimson → winter blue again.
const SEASON_ANCHORS: [(f64, f64, &str); 5] = [
    (20.0, 215.0, "winter"),  // 大寒: cool blue
    (95.0, 340.0, "spring"),  // 清明: sakura
    (172.0, 480.0, "summer"), // 夏至: fresh green (120°)
    (296.0, 378.0, "autumn"), // 霜降: maple (18°)
    (385.0, 215.0, "winter"), // the next 大寒
];

/// The hue (degrees, 0..360) this term's colours lean toward, and the season it is nearest (`winter`, `spring`,
/// `summer`, `autumn`): sampled at the term's start, as `warmth`, so the fortnight shares one value.
pub fn season_hue(term: SolarTerm) -> (f64, &'static str) {
    let mut doy = f64::from(Date::new(2001, term.start.0, term.start.1).day_of_year());
    if doy < SEASON_ANCHORS[0].0 {
        doy += 365.0;
    }
    let i = SEASON_ANCHORS
        .windows(2)
        .position(|w| doy >= w[0].0 && doy < w[1].0)
        .unwrap_or(SEASON_ANCHORS.len() - 2);
    let (a, b) = (SEASON_ANCHORS[i], SEASON_ANCHORS[i + 1]);
    let t = (doy - a.0) / (b.0 - a.0);
    let hue = (a.1 + (b.1 - a.1) * t).rem_euclid(360.0);
    let near = if t < 0.5 { a.2 } else { b.2 };
    ((hue * 1e3).round() / 1e3, near)
}

/// Warmth in -1.0 (coldest, ~大寒) ..= 1.0 (hottest, ~大暑), sampled at the term's start
/// so the whole fortnight shares one value (24 discrete steps, not a continuous drift).
pub fn warmth(term: SolarTerm) -> f64 {
    let doy = Date::new(2001, term.start.0, term.start.1).day_of_year();
    let w = -(2.0 * std::f64::consts::PI * (f64::from(doy) - 24.0) / 365.0).cos();
    // Round so the golden/determinism tests never depend on libm last-digit differences.
    (w * 1e6).round() / 1e6
}
