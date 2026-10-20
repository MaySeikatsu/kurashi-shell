{ lib, rustPlatform, dbus, python3, pkg-config, libpulseaudio, linux-pam }:

let
  fs = lib.fileset;
in
rustPlatform.buildRustPackage {
  pname = "kurashi";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  # Rust workspace + runtime data — archive/ and docs/ never invalidate the package build.
  src = fs.toSource {
    root = ../.;
    # Screenshots are review artefacts, not runtime data.
    fileset = fs.difference (fs.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
      ../fixtures
      ../i18n
      ../palettes
      ../profiles
      ../templates
      ../decors
      ../frontend
      ../settings
      ../mods
    ]) (fs.unions [
      (fs.maybeMissing ../frontend/shots)
      (fs.maybeMissing ../settings/shots)
    ]);
  };

  cargoLock.lockFile = ../Cargo.lock;
  # kurashi-audio links libpulse (pipewire-pulse speaks it too, K-audio).
  # kurashi-auth's `pam` feature binds libpam via bindgen (CONTRACT #4a).
  nativeBuildInputs = [ pkg-config rustPlatform.bindgenHook ];
  buildInputs = [ libpulseaudio linux-pam ];
  # kurashi-services tests run fake D-Bus objects on a private dbus-daemon; kurashid's host tests
  # run a Python fake host.
  nativeCheckInputs = [
    dbus
    python3
  ];
  # The build sandbox has no /usr/bin/env, so the fake host's `#!/usr/bin/env python3` must point at
  # the store's python3 before the tests start it. patchShebangs only touches executable files, and
  # the tracked script is 0644 (the test makes its copy executable).
  preCheck = ''
    chmod +x crates/kurashid/tests/data/hosts/fake-host.py
    patchShebangs crates/kurashid/tests/data/hosts
  '';

  # kurashid finds i18n/, palettes/, profiles/ (bundled) and the frontend here (crates/kurashid/src/i18n.rs).
  env.KURASHI_DATA_DIR = "${placeholder "out"}/share/kurashi";
  postInstall = ''
    mkdir -p $out/share/kurashi
    cp -r i18n palettes profiles templates frontend settings mods $out/share/kurashi/
  '';

  meta = {
    description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kurashi";
    platforms = lib.platforms.linux;
  };
}
