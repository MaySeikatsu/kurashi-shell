{ lib, rustPlatform }:

let
  fs = lib.fileset;
in
rustPlatform.buildRustPackage {
  pname = "kurashi";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  # Rust workspace + runtime data — probes/ and docs/ never invalidate the package build.
  src = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
      ../fixtures
      ../i18n
      ../palettes
      ../frontend
    ];
  };

  cargoLock.lockFile = ../Cargo.lock;

  # kurashid finds i18n/, palettes/ and the frontend here (crates/kurashid/src/i18n.rs).
  env.KURASHI_DATA_DIR = "${placeholder "out"}/share/kurashi";
  postInstall = ''
    mkdir -p $out/share/kurashi
    cp -r i18n palettes frontend $out/share/kurashi/
  '';

  meta = {
    description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kurashi";
    platforms = lib.platforms.linux;
  };
}
