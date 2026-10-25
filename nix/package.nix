{ lib, rustPlatform, dbus, python3, pkg-config, libpulseaudio, linux-pam, callPackage }:

let
  fs = lib.fileset;
  # The shell's icon font subset (W39-block, I194; W41, row 445): installed with the package, so every profile that
  # has it gets the fonts kurashi-theme prefers (font.icons). The modules' font defaults take the same derivation.
  iconFont = callPackage ./icon-font.nix { };
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
      ../looks
      ../styles
      ../frontend
      ../settings
      ../mods
      # The greeter (W28): its QML and the links `core`/`components` into frontend/.
      ../greeter
    ]) (fs.unions [
      (fs.maybeMissing ../frontend/shots)
      (fs.maybeMissing ../settings/shots)
      (fs.maybeMissing ../greeter/shots)
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
  # The tests read the i18n tables through KURASHI_DATA_DIR (crates/kurashid/src/i18n.rs), which the binary takes at compile
  # time as $out/share/kurashi, and $out has no data until installPhase: the keys tests found no strings there (W41 check
  # run). The check phase reads the source tree's i18n/ instead, as a `cargo test` in the checkout does.
  preCheck = ''
    export KURASHI_DATA_DIR=$PWD
    chmod +x crates/kurashid/tests/data/hosts/fake-host.py
    patchShebangs crates/kurashid/tests/data/hosts
  '';

  # kurashid finds i18n/, palettes/, profiles/ (bundled) and the frontend here (crates/kurashid/src/i18n.rs).
  env.KURASHI_DATA_DIR = "${placeholder "out"}/share/kurashi";
  postInstall = ''
    mkdir -p $out/share/kurashi
    cp -r i18n palettes profiles templates frontend settings mods greeter $out/share/kurashi/
    mkdir -p $out/share/fonts/truetype
    cp ${iconFont}/share/fonts/truetype/*.ttf $out/share/fonts/truetype/
  '';

  meta = {
    description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kurashi";
    platforms = lib.platforms.linux;
  };
}
