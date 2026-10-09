# quickshell probe
Run (inside the sandbox env, with kurashi-mock up): `qs -p probes/quickshell`
or `nix run ./probes/quickshell`. QML only, no build step.
Rebuild shader after editing: `qsb --qt6 -o shader.frag.qsb shader.frag` (devShell has qsb).
