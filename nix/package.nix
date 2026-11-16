{
  lib,
  craneLib,
  dbus,
  python3,
  pkg-config,
  libpulseaudio,
  linux-pam,
  rustPlatform,
  runCommand,
  writeText,
  makeBinaryWrapper,
  callPackage,
}:

# Split so an edit rebuilds only what it touches (I290–I293):
# - deps: the ~400 dependency crates (crane `buildDepsOnly`); only Cargo.lock and the Cargo.toml files invalidate it.
# - bin: our crates, from the Rust sources and the data they compile in (include_str!) — no QML, no runtime strings.
# - the package: frontend, settings, mods, i18n, … copied next to wrappers that set KURASHI_DATA_DIR =
#   $out/share/kurashi (read at run time, I291), so `bin` does not depend on the data; a QML or string edit rebuilds
#   only this copy (seconds). The tests are `passthru.cargoTests` (flake check `tests`), not part of `nix build`.
let
  fs = lib.fileset;
  # The shell's icon font subset (W39-block, I194; W41, row 445): installed with the package, so every profile that
  # has it gets the fonts kurashi-theme prefers (font.icons). The modules' font defaults take the same derivation.
  iconFont = callPackage ./icon-font.nix { };

  pname = "kurashi";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  # Screenshots are review artefacts, not runtime data.
  shots = fs.unions [
    (fs.maybeMissing ../frontend/shots)
    (fs.maybeMissing ../settings/shots)
    (fs.maybeMissing ../greeter/shots)
    # W59.2's qmltestrunner tests and their Quickshell stub are for `frontend/test-motion.sh`, not the package.
    (fs.maybeMissing ../frontend/core/motion/tests)
  ];

  # What the Rust build reads: the workspace plus the files our crates embed with include_str! (looks, styles and
  # palettes in kurashi-theme, the motion packs in kurashi-motion, the doctor's strings in kurashi) and the IPC
  # fixtures. An edit to these still rebuilds our crates — never the deps.
  rustSrc = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../Cargo.toml
      ../Cargo.lock
      # W90 (K157): jemalloc's configuration is read when its C library is built.
      ../.cargo/config.toml
      ../crates
      ../fixtures
      ../looks
      ../styles
      ../motion
      ../palettes
      ../i18n/en/doctor.toml
      ../i18n/ja/doctor.toml
    ];
  };

  # The tests read the whole tree as a `cargo test` in the checkout does (i18n tables, templates, mods' manifests…).
  testSrc = fs.toSource {
    root = ../.;
    fileset = fs.difference (fs.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../.cargo/config.toml
      ../crates
      ../fixtures
      ../i18n
      ../palettes
      ../profiles
      ../templates
      ../looks
      ../styles
      ../motion
      ../frontend
      ../settings
      ../mods
      # K154: kurashi-mods' test holds docs/MODS.md's table of extension points to the registry.
      ../docs/MODS.md
      # The generated example is held current by kurashid's test (session 33; the check was red without the file, B146).
      ../config.toml.example
      # W53.0b (K80): the styles' sound cues and cursor themes (original, CC0).
      ../sounds
      ../cursors
      # The greeter (W28): its QML and the links `core`/`components` into frontend/.
      ../greeter
    ]) shots;
  };

  dataSrc = fs.toSource {
    root = ../.;
    fileset = fs.difference (fs.unions [
      ../i18n
      ../palettes
      ../profiles
      ../templates
      ../frontend
      ../settings
      ../mods
      ../sounds
      ../cursors
      ../greeter
    ]) shots;
  };

  commonArgs = {
    inherit pname version;
    src = rustSrc;
    strictDeps = true;
    # kurashi-audio links libpulse (pipewire-pulse speaks it too, K-audio).
    # kurashi-auth's `pam` feature binds libpam via bindgen (CONTRACT #4a).
    nativeBuildInputs = [ pkg-config rustPlatform.bindgenHook ];
    buildInputs = [ libpulseaudio linux-pam ];
  };

  # K156 (W97): a version bump must not rebuild the ~400 dependencies. Every PR bumps `[workspace.package] version`
  # (K151); the version stood in the dependency derivation three times — as its own `version`, in the root Cargo.toml
  # and in Cargo.lock (each member's entry) — so every PR rebuilt them in release. The dependency derivation is built
  # from a source that does not carry it:
  # - the manifests crane writes for its dummy source drop `workspace.package.version` and each member's `version`
  #   (cargo reads a manifest without one as 0.0.0);
  # - the lock file is this tree's with the members' entries at 0.0.0, written at evaluation (no import from a
  #   derivation: `builtins.readFile` of a path, `writeText` of the result, so its hash follows its content);
  # - the vendored registry comes from the real lock (the members have no source and are not part of it).
  # To check: `nix eval --raw .#kurashi.cargoArtifacts.drvPath` before and after a bump of the version names the same
  # derivation (session 35: it does, and the second `nix build` compiled no dependency).
  members = lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ../crates));
  memberNames = map (d: (lib.importTOML (../crates + "/${d}/Cargo.toml")).package.name) members;
  lockWithoutVersion = writeText "Cargo.lock" (
    builtins.replaceStrings
      (map (n: "name = \"${n}\"\nversion = \"${version}\"\n") memberNames)
      (map (n: "name = \"${n}\"\nversion = \"0.0.0\"\n") memberNames)
      (builtins.readFile ../Cargo.lock)
  );
  depsSrc = craneLib.mkDummySrc {
    # Without Cargo.lock: crane would copy the tree's own (with the version) beside the manifests.
    src = fs.toSource {
      root = ../.;
      fileset = fs.unions [
        ../Cargo.toml
        ../.cargo/config.toml
        ../crates
      ];
    };
    cargoLock = lockWithoutVersion;
    cleanCargoTomlFilter =
      path:
      craneLib.filters.cargoTomlDefault path
      && path != [ "workspace" "package" "version" ]
      && path != [ "package" "version" ];
  };

  # Also compiles the dev-dependencies (crane's `doCheck`), so `tests` reuses it. The `cargo check` pass is skipped:
  # nothing here runs clippy.
  cargoArtifacts = craneLib.buildDepsOnly (
    (removeAttrs commonArgs [ "src" ])
    // {
      version = "0";
      dummySrc = depsSrc;
      cargoVendorDir = craneLib.vendorCargoDeps { cargoLock = ../Cargo.lock; };
      cargoCheckCommand = "true";
    }
  );

  bin = craneLib.buildPackage (
    commonArgs
    // {
      pname = "${pname}-bin";
      inherit cargoArtifacts;
      doCheck = false;
    }
  );

  tests = craneLib.cargoTest (
    commonArgs
    // {
      pname = "${pname}-tests";
      src = testSrc;
      inherit cargoArtifacts;
      # kurashi-services tests run fake D-Bus objects on a private dbus-daemon; kurashid's host tests
      # run a Python fake host.
      nativeCheckInputs = [
        dbus
        python3
      ];
      # The build sandbox has no /usr/bin/env, so the fake host's `#!/usr/bin/env python3` must point at
      # the store's python3 before the tests start it. patchShebangs only touches executable files, and
      # the tracked script is 0644 (the test makes its copy executable).
      # The tests read the i18n tables through KURASHI_DATA_DIR (crates/kurashid/src/i18n.rs): the source tree's.
      preCheck = ''
        export KURASHI_DATA_DIR=$PWD
        chmod +x crates/kurashid/tests/data/hosts/fake-host.py
        patchShebangs crates/kurashid/tests/data/hosts
      '';
    }
  );

in
# kurashid finds i18n/, palettes/, profiles/ (bundled) and the frontend here (crates/kurashid/src/i18n.rs). The data is
# copied, not symlinked from a third derivation: the frontend, the mods' QML and the greeter import each other by
# relative paths, and one file reached through two store paths would be two QML types (two singletons).
runCommand "${pname}-${version}"
  {
    inherit pname version;
    nativeBuildInputs = [ makeBinaryWrapper ];
    passthru = {
      # Not `bin`: lib.getBin (writeShellApplication's runtimeInputs, makeBinPath) takes an attribute of that name for the
      # package's bin output, and the unwrapped binaries find no data (the `nix run .` app ran them, session 17).
      unwrapped = bin;
      inherit cargoArtifacts;
      # Not `tests`: nixpkgs tooling expects an attribute set there.
      cargoTests = tests;
      # The devShell builds the same crates (flake.nix).
      rustNativeBuildInputs = commonArgs.nativeBuildInputs;
      rustBuildInputs = commonArgs.buildInputs;
    };
    meta = {
      description = "Kurashi-shell daemon (kurashid), CLI (kurashi) and mock daemon";
      license = lib.licenses.gpl3Plus;
      mainProgram = "kurashi";
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p $out/bin $out/share/kurashi $out/share/fonts/truetype
    cp -r ${dataSrc}/. $out/share/kurashi/
    cp ${iconFont}/share/fonts/truetype/*.ttf $out/share/fonts/truetype/
    # Every option, annotated (session 33; generated, tests/config_example.rs)
    install -Dm644 ${../config.toml.example} $out/share/doc/kurashi/config.toml.example
    # Wrappers exec the real binaries, so the processes keep their names. --set-default keeps an explicit
    # KURASHI_DATA_DIR (the sandboxes, the greeter) working.
    for b in ${bin}/bin/*; do
      makeWrapper $b $out/bin/$(basename $b) --set-default KURASHI_DATA_DIR $out/share/kurashi
    done
  ''
