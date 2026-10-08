{ lib, rustPlatform }:

let
  fs = lib.fileset;
in
rustPlatform.buildRustPackage {
  pname = "kurashi";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  # Only the Rust workspace — probes/ and docs/ never invalidate the package build.
  src = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
      ../fixtures
    ];
  };

  cargoLock.lockFile = ../Cargo.lock;

  meta = {
    description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kurashi";
    platforms = lib.platforms.linux;
  };
}
