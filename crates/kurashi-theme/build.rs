// The bundled palettes are embedded with include_str! from outside the crate; make palette edits
// rebuild the crate (cargo did not notice them, found by the golden-screenshot harness).
fn main() {
    println!("cargo:rerun-if-changed=../../palettes");
}
