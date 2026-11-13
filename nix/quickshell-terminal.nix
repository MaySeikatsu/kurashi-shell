# The terminal host's Quickshell (W83): stock Quickshell with QMLTermWidget (nix/qmltermwidget.nix) on its QML import
# path, installed as `qs-terminal`, so a terminal runs in its own process (a pty or plugin fault never takes the shell
# down) and the shell's own `qs` never loads the plugin (K3). Unpatched, unlike `qs-webengine`.
{
  lib,
  quickshell,
  qt6,
  makeWrapper,
  runCommand,
  qmltermwidget,
}:
runCommand "qs-terminal-${quickshell.version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = { inherit qmltermwidget; };
    meta.mainProgram = "qs-terminal";
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${quickshell}/bin/quickshell $out/bin/qs-terminal \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qmltermwidget}/${qt6.qtbase.qtQmlPrefix}
  ''
