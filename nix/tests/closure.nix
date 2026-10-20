# Closure check (K39, W20-webdock-nix): the base package's closure carries no QtWebEngine, the web dock's does.
# flake.nix wires it as checks.<system>.webdock-closure. `base` must be free of QtWebEngine, `webdock` must carry it.
# The negative proof: pass the web dock as `base`; the build then fails (`nix build --no-link -f` on such a file).
{
  pkgs,
  base,
  webdock,
}:

let
  # closureInfo writes every store path of the closure into `store-paths`.
  carriesQtWebEngine =
    package: "grep -q qtwebengine ${pkgs.closureInfo { rootPaths = [ package ]; }}/store-paths";
in
pkgs.runCommand "kurashi-closure-webdock" { } ''
  if ${carriesQtWebEngine base}; then
    echo "the base package's closure carries QtWebEngine: ${base}" >&2
    exit 1
  fi
  if ! ${carriesQtWebEngine webdock}; then
    echo "the web dock's closure carries no QtWebEngine: ${webdock}" >&2
    exit 1
  fi
  touch $out
''
