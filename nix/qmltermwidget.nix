# The terminal mod's QML terminal (W83): QMLTermWidget, cool-retro-term's QML port of qtermwidget, at its Qt 6 port
# (master since 2026-01, v2.0). nixpkgs packages only the Qt 5 0.2 line, so this builds the Qt 6 one against the same
# qt6 as nixpkgs' Quickshell (a QML plugin must match its host's Qt). Installs `QMLTermWidget` under lib/qt-6/qml.
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation {
  pname = "qmltermwidget";
  version = "2.0-unstable-2026-05-31";

  src = fetchFromGitHub {
    owner = "Swordfish90";
    repo = "qmltermwidget";
    rev = "8913504fa2ebd220ebe7c680c32954e1b3c035c5";
    hash = "sha256-Tm4ABLH4dquCNyee8vrlWN5S5ehtZBFU2rseW6IA/dw=";
  };

  # The shell's palette and material from QML (W83): `setColors([fg, bg, c0 … c15])` and `setBackgroundOpacity(a)`.
  # Upstream only loads named .colorscheme files, cached by name for the process, so a theme change could not repaint.
  patches = [ ./patches/qmltermwidget-palette.patch ];

  nativeBuildInputs = [ qt6.qmake ];
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # Install into $out, not Qt's own store path; and only once: the colour schemes and keyboard layouts are already
  # installed as `assets` (nixpkgs' do-not-copy-artifacts-twice, the same fault on this line).
  postPatch = ''
    substituteInPlace qmltermwidget.pro \
      --replace-fail '$$[QT_INSTALL_QML]' '$$PREFIX/${qt6.qtbase.qtQmlPrefix}/' \
      --replace-fail 'INSTALLS += target qmldir assets colorschemes colorschemes2 kblayouts kblayouts2 scrollbar' \
        'INSTALLS += target qmldir assets'
    # The scrollback from QML (the mod's `scrollback`); upstream keeps 1000 lines and offers no setter to QML.
    substituteInPlace lib/ksession.h \
      --replace-fail '    void setHistorySize(int lines);' '    Q_INVOKABLE void setHistorySize(int lines);'
  '';

  dontWrapQtApps = true;

  meta = {
    description = "QML port of qtermwidget (Qt 6), the terminal kurashi's terminal mod draws with";
    homepage = "https://github.com/Swordfish90/qmltermwidget";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
