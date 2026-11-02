//! Springs by response and bounce (K83, brief §4): SwiftUI's model, mass 1, mapped 1:1 onto niri's `damping-ratio` and
//! `stiffness`. The closed form for every damping regime, its settle time and overshoot, and the plot Settings draws.
//!
//! `stiffness = (2π / response)²`; `damping = 4π (1 − bounce) / response` for bounce ≥ 0, `4π / (response (1 + bounce))`
//! below (overdamped) — so the damping ratio is `1 − bounce`, or `1 / (1 + bounce)`. Times are seconds inside, ms at
//! the edges. (K42's `spring_q` springs are QML SpringAnimation's integrator; the frontend runs those, not this.)

use std::f64::consts::PI;

/// Within this of the target the spring is at rest (Settings' settle time, the frontend's stop).
pub const EPSILON: f64 = 0.001;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Spring {
    /// N/m with mass 1 (1/s²).
    pub stiffness: f64,
    /// N·s/m with mass 1 (1/s).
    pub damping: f64,
}

impl Spring {
    /// A spring by its response (ms) and bounce (−0.5…0.9; 0 = critically damped).
    pub fn from_response(response_ms: f64, bounce: f64) -> Spring {
        let t = (response_ms / 1000.0).max(1e-3);
        let stiffness = (2.0 * PI / t).powi(2);
        let damping = if bounce >= 0.0 {
            4.0 * PI * (1.0 - bounce) / t
        } else {
            4.0 * PI / (t * (1.0 + bounce))
        };
        Spring { stiffness, damping }
    }

    /// The inverse of [`Spring::from_response`]: (response ms, bounce).
    pub fn response_bounce(&self) -> (f64, f64) {
        let response = 2.0 * PI / self.stiffness.sqrt();
        let zeta = self.damping_ratio();
        let bounce = if zeta <= 1.0 {
            1.0 - zeta
        } else {
            1.0 / zeta - 1.0
        };
        (response * 1000.0, bounce)
    }

    /// ω₀ (rad/s).
    pub fn omega(&self) -> f64 {
        self.stiffness.sqrt()
    }

    /// ζ: 1 critical, below 1 it overshoots.
    pub fn damping_ratio(&self) -> f64 {
        self.damping / (2.0 * self.omega())
    }

    /// Position at `t_ms` moving from 0 to 1, starting with velocity `v0` (progress per second).
    pub fn position(&self, t_ms: f64, v0: f64) -> f64 {
        1.0 + self.offset(t_ms / 1000.0, v0).0
    }

    /// Velocity (progress per second) at `t_ms`.
    pub fn velocity(&self, t_ms: f64, v0: f64) -> f64 {
        self.offset(t_ms / 1000.0, v0).1
    }

    /// (u, u') where u = x − 1, u(0) = −1, u'(0) = v0.
    fn offset(&self, t: f64, v0: f64) -> (f64, f64) {
        let w = self.omega();
        let z = self.damping_ratio();
        let u0 = -1.0;
        if (z - 1.0).abs() < 1e-9 {
            // Critically damped: u = e^{−ωt} (u0 + (v0 + ω u0) t).
            let b = v0 + w * u0;
            let e = (-w * t).exp();
            (e * (u0 + b * t), e * (b - w * (u0 + b * t)))
        } else if z < 1.0 {
            let wd = w * (1.0 - z * z).sqrt();
            let b = (v0 + z * w * u0) / wd;
            let e = (-z * w * t).exp();
            let (s, c) = (wd * t).sin_cos();
            let u = e * (u0 * c + b * s);
            let du = e * ((-z * w) * (u0 * c + b * s) + wd * (b * c - u0 * s));
            (u, du)
        } else {
            let q = w * (z * z - 1.0).sqrt();
            let (r1, r2) = (-z * w + q, -z * w - q);
            let c2 = (v0 - r1 * u0) / (r2 - r1);
            let c1 = u0 - c2;
            let (e1, e2) = ((r1 * t).exp(), (r2 * t).exp());
            (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
        }
    }

    /// How long it takes from rest at 0 until it stays within [`EPSILON`] of 1 (ms, to the millisecond).
    pub fn settle_ms(&self) -> f64 {
        let mut last_out = 0.0;
        // Twelve time constants of the slowest decay are always enough (e^{-12} (1 + 12) < ε).
        let (w, z) = (self.omega(), self.damping_ratio());
        let rate = if z <= 1.0 {
            z * w
        } else {
            w * (z - (z * z - 1.0).sqrt())
        };
        let horizon = (12.0 / rate).max(0.05) * 1000.0;
        let mut t = 0.0;
        while t <= horizon {
            if (self.position(t, 0.0) - 1.0).abs() >= EPSILON {
                last_out = t;
            }
            t += 1.0;
        }
        last_out + 1.0
    }

    /// The overshoot past 1 from rest (0 when it never passes 1).
    pub fn overshoot(&self) -> f64 {
        let z = self.damping_ratio();
        if z >= 1.0 {
            0.0
        } else {
            (-z * PI / (1.0 - z * z).sqrt()).exp()
        }
    }

    /// Settings' plot: 64 points (t ms, position) from 0 to the settle time.
    pub fn plot(&self) -> Vec<(f64, f64)> {
        let end = self.settle_ms();
        (0..64)
            .map(|i| {
                let t = end * f64::from(i) / 63.0;
                (t, self.position(t, 0.0))
            })
            .collect()
    }

    /// niri's `spring { damping-ratio stiffness }` for this spring (niri: mass 1, seconds).
    pub fn niri(&self) -> (f64, f64) {
        (self.damping_ratio(), self.stiffness)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_and_bounce_map_onto_stiffness_and_damping() {
        let s = Spring::from_response(500.0, 0.25);
        assert!((s.stiffness - (2.0 * PI / 0.5).powi(2)).abs() < 1e-9);
        assert!((s.damping_ratio() - 0.75).abs() < 1e-9);
        let (r, b) = s.response_bounce();
        assert!((r - 500.0).abs() < 1e-6 && (b - 0.25).abs() < 1e-9);
        // Overdamped: ratio 1 / (1 + bounce).
        let o = Spring::from_response(400.0, -0.2);
        assert!((o.damping_ratio() - 1.25).abs() < 1e-9);
        let (r, b) = o.response_bounce();
        assert!((r - 400.0).abs() < 1e-6 && (b + 0.2).abs() < 1e-9);
        // niri's damping ratio is 1 − bounce.
        assert!((Spring::from_response(550.0, 0.45).niri().0 - 0.55).abs() < 1e-9);
    }

    #[test]
    fn closed_form_starts_at_rest_and_ends_home() {
        for bounce in [-0.5, -0.2, 0.0, 0.25, 0.45, 0.65, 0.9] {
            let s = Spring::from_response(550.0, bounce);
            assert!(s.position(0.0, 0.0).abs() < 1e-12, "{bounce}");
            assert!(s.velocity(0.0, 0.0).abs() < 1e-9, "{bounce}");
            assert!((s.position(20_000.0, 0.0) - 1.0).abs() < 1e-6, "{bounce}");
            // A given start velocity is honoured.
            assert!((s.velocity(0.0, 3.0) - 3.0).abs() < 1e-9, "{bounce}");
        }
    }

    #[test]
    fn velocity_is_the_derivative_of_position() {
        for bounce in [-0.3, 0.0, 0.45] {
            let s = Spring::from_response(500.0, bounce);
            for t in [10.0, 120.0, 333.0] {
                let num = (s.position(t + 0.01, 1.5) - s.position(t - 0.01, 1.5)) / 0.02 * 1000.0;
                assert!((num - s.velocity(t, 1.5)).abs() < 1e-3, "{bounce} {t}");
            }
        }
    }

    #[test]
    fn overshoot_matches_the_sampled_peak() {
        for bounce in [0.0, 0.25, 0.45, 0.65] {
            let s = Spring::from_response(600.0, bounce);
            let peak = (0..3000)
                .map(|t| s.position(f64::from(t), 0.0))
                .fold(0.0, f64::max);
            assert!(
                (peak - 1.0 - s.overshoot()).abs() < 1e-4,
                "{bounce}: {peak} vs {}",
                s.overshoot()
            );
        }
        assert_eq!(Spring::from_response(600.0, -0.3).overshoot(), 0.0);
    }

    #[test]
    fn settle_time_against_the_envelope() {
        // Underdamped: |u| ≤ e^{−ζωt} / √(1 − ζ²), so it settles no later than that envelope reaches ε.
        for bounce in [0.25, 0.45, 0.65] {
            let s = Spring::from_response(500.0, bounce);
            let z = s.damping_ratio();
            let bound = ((1.0 - z * z).sqrt() * EPSILON).ln().abs() / (z * s.omega()) * 1000.0;
            let settle = s.settle_ms();
            assert!(settle <= bound + 1.0, "{bounce}: {settle} > {bound}");
            assert!(settle > 0.3 * bound, "{bounce}: {settle} ≪ {bound}");
            assert!((s.position(settle, 0.0) - 1.0).abs() < EPSILON);
        }
        // Critically damped: u = −e^{−ωt}(1 + ωt) — solve for ε by bisection.
        let s = Spring::from_response(450.0, 0.0);
        let w = s.omega();
        let (mut lo, mut hi) = (0.0, 10.0);
        for _ in 0..80 {
            let m = 0.5 * (lo + hi);
            if (-w * m).exp() * (1.0 + w * m) > EPSILON {
                lo = m;
            } else {
                hi = m;
            }
        }
        assert!((s.settle_ms() - hi * 1000.0).abs() <= 1.5);
        // More bounce, longer to settle.
        assert!(
            Spring::from_response(500.0, 0.65).settle_ms()
                > Spring::from_response(500.0, 0.25).settle_ms()
        );
    }

    #[test]
    fn plot_has_64_points_from_rest_to_home() {
        let p = Spring::from_response(550.0, 0.45).plot();
        assert_eq!(p.len(), 64);
        assert_eq!(p[0], (0.0, 0.0));
        assert!((p[63].1 - 1.0).abs() < EPSILON);
        assert!(
            p.iter().any(|(_, x)| *x > 1.1),
            "a bouncy spring shows its overshoot"
        );
    }
}
