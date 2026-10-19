# The web host's Quickshell (K39): stock Quickshell with nix/patches/quickshell-webengine.patch (argv[0] for
# QtWebEngine, pragma ShareOpenGLContexts) and QtWebEngine's QML modules on the import path. Installed as
# `qs-webengine`, so it never shadows the shell's own `qs`; the shell itself keeps stock Quickshell (K3).
{
  lib,
  quickshell,
  qt6,
  makeWrapper,
  runCommand,
}:
let
  patched = quickshell.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/quickshell-webengine.patch ];
  });
  qml = lib.makeSearchPath "lib/qt-6/qml" [
    qt6.qtwebengine
    qt6.qtwebchannel
    qt6.qtpositioning
  ];
in
runCommand "qs-webengine-${quickshell.version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = { inherit patched; };
    meta.mainProgram = "qs-webengine";
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${patched}/bin/quickshell $out/bin/qs-webengine \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qml}
  ''
