//! Misuse of `#[derive(KurashiSchema)]` must fail to compile with a helpful message.
//! Refresh the `.stderr` snapshots with `TRYBUILD=overwrite` (they are rustc-version specific).

#[test]
fn compile_fail() {
    trybuild::TestCases::new().compile_fail("tests/ui/*.rs");
}
