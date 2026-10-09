//! Pressure stall information (`/proc/pressure/{cpu,memory,io}`): the share of time tasks waited on the
//! resource. It explains slowness better than a percentage ("memory pressure: some 12 %",
//! docs/ux/sysmon.md "Pressure, not just percent"). Absent kernels or files give None, never 0.

use crate::roots::Roots;

/// Percent of time at least one task (`some`) or all non-idle tasks (`full`) stalled, last 10 s.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Psi {
    pub some: f64,
    pub full: Option<f64>,
}

pub fn parse(text: &str) -> Option<Psi> {
    let mut some = None;
    let mut full = None;
    for line in text.lines() {
        let mut parts = line.split_ascii_whitespace();
        let kind = parts.next()?;
        let avg10 = parts.find_map(|kv| kv.strip_prefix("avg10=")?.parse::<f64>().ok());
        match kind {
            "some" => some = avg10,
            "full" => full = avg10,
            _ => {}
        }
    }
    Some(Psi { some: some?, full })
}

pub fn read(roots: &Roots, resource: &str) -> Option<Psi> {
    parse(&roots.read(roots.proc.join("pressure").join(resource))?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn some_and_full_lines_take_avg10() {
        let psi = parse(
            "some avg10=12.34 avg60=1.00 avg300=0.50 total=99\n\
             full avg10=3.10 avg60=0.00 avg300=0.00 total=5\n",
        )
        .unwrap();
        assert_eq!(
            psi,
            Psi {
                some: 12.34,
                full: Some(3.10)
            }
        );
    }

    #[test]
    fn cpu_pressure_has_no_full_line_on_older_kernels() {
        let psi = parse("some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n").unwrap();
        assert_eq!(psi.full, None);
    }

    #[test]
    fn missing_file_is_absent() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        assert_eq!(read(&roots, "memory"), None);
    }
}
