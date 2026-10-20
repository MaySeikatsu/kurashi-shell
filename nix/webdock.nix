# The web dock's package (K38, K39): the host's Quickshell (`qs-webengine`, nix/quickshell-webengine.nix) and
# `xdg-open`, which kurashid runs for "open in browser" (capability `exec:xdg-open`). It stays apart from `kurashi`
# so QtWebEngine never enters the base closure; Home-Manager and NixOS install it only with the dock on
# (`programs.kurashi.webdock.enable`).
{
  lib,
  symlinkJoin,
  xdg-utils,
  quickshell-webengine,
}:

symlinkJoin {
  name = "kurashi-webdock-${(lib.importTOML ../Cargo.toml).workspace.package.version}";
  paths = [
    quickshell-webengine
    xdg-utils
  ];
  meta = {
    description = "Kurashi-shell web dock: the web host's qs-webengine (patched Quickshell with QtWebEngine) and xdg-open";
    mainProgram = "qs-webengine";
    platforms = lib.platforms.linux;
  };
}
