# gpui probe

Build: `nix develop ./probes/gpui -c cargo build --release --manifest-path probes/gpui/Cargo.toml`
(`git add` new files first; flakes only see tracked files.)
Run (inside a sandbox / session with `KURASHI_SOCKET` set): `probes/gpui/run.sh`
Bench: `nix develop ./probes/gpui -c python3 tools/bench/measure.py --name gpui --warmup 10 --idle 30 -- $PWD/probes/gpui/run.sh`
See REPORT.md.
