{ lib, rustPlatform, dbus, pkg-config, libpulseaudio, linux-pam }:

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
  # kurashi-services tests run fake D-Bus objects on a private dbus-daemon.
  nativeCheckInputs = [ dbus ];

  # kurashid finds i18n/, palettes/ and the frontend here (crates/kurashid/src/i18n.rs).
  env.KURASHI_DATA_DIR = "${placeholder "out"}/share/kurashi";
  postInstall = ''
    mkdir -p $out/share/kurashi
    cp -r i18n palettes frontend settings mods $out/share/kurashi/
  '';

  meta = {
    description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kurashi";
    platforms = lib.platforms.linux;
  };
}
