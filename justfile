# Kurashi-shell task runner (use inside `nix develop`).

default:
    @just --list

# fmt-check + clippy (deny warnings) + tests (nextest, K153: half of `cargo test`'s time; doctests apart, nextest runs
# none) + the launch script's tests + the icon subset + the clone ratchet (rule 10)
check:
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo nextest run --workspace
    cargo test --workspace --doc
    sh frontend/test-launch.sh
    sh tools/check-icon-names.sh
    python3 tools/clones.py --check

# The merge gate (K153, rule 11): everything a merge to `main` needs, once, at the end of the work — `just check`, the
# suites' merge set, the Home-Manager evaluation and the package. It writes the commit it passed on to
# tools/bench/results/gate.txt; the merge or the PR cites that line. `just gate --no-suites` for a change no suite reads
# (docs, tools): the line then says so.
gate *ARGS:
    #!/usr/bin/env bash
    set -uo pipefail
    suites=1
    for a in {{ARGS}}; do case "$a" in --no-suites) suites=0 ;; *) echo "gate: unknown argument $a"; exit 2 ;; esac; done
    sha=$(git rev-parse --short HEAD)
    [ -z "$(git status --porcelain)" ] || sha="$sha+uncommitted"
    step() { echo "== gate: $*"; "$@" || { echo "gate: FAILED at: $* ($sha)"; exit 1; }; }
    step just check
    if [ "$suites" = 1 ]; then step just suites; fi
    step just nix-eval-test
    step nix build .#kurashi --no-link
    mkdir -p tools/bench/results
    known=$(grep -vc -e '^#' -e '^$' tools/suites-known-failing.txt)
    line="gate: passed on $sha at $(date -u +%Y-%m-%dT%H:%MZ): check, $([ "$suites" = 1 ] && echo "suites (merge set; $known known failing as on main)" || echo "no suites"), hm-eval, nix build"
    echo "$line" | tee tools/bench/results/gate.txt

# Build artifacts older than DAYS leave `target/`, then the oldest until it is under CAP (K153, rule 11; the user,
# session 34: 60 GB). Session start and end. The agents' build dirs are removed by hand after their merge (B23).
sweep days="7" cap="60GB":
    cargo sweep --time {{days}}
    cargo sweep --maxsize {{cap}}
    @du -sh "${CARGO_TARGET_DIR:-target}" | awk '{print "sweep: target is now " $1}'

# What the Rust loop costs here: no-op, link, daemon, leaf mod, schema (tools/bench/build-timings.sh)
timings:
    tools/bench/build-timings.sh

# Cross-file clones by language, the pairs sharing most (rule 10); `just check` runs the ratchet
clones *ARGS:
    python3 tools/clones.py {{ARGS}}

fmt:
    cargo fmt --all

build:
    cargo build --workspace --release

# Run the real daemon (M0: handshake only)
dev:
    cargo run -p kurashid

# Fake daemon serving the probe subset (docs/PROTOCOL.md §8)
mock *ARGS:
    cargo run -p kurashi-mock -- {{ARGS}}

# Headless sway sandbox: `just sandbox start|stop|env [name]`
sandbox action="start" name="dev":
    tools/bench/sandbox.sh {{action}} {{name}}

# Measure a frontend: `just bench <name> -- <command to launch it>`
bench name *CMD:
    cargo build --workspace --release
    python3 tools/bench/measure.py --name {{name}} -- {{CMD}}

# Frontend suites in parallel, a failure re-run alone (tools/test-suites.sh): `just suites`, `just suites --changed`,
# `just suites dock frame`, `just suites --all`
suites *ARGS:
    tools/test-suites.sh {{ARGS}}

nix-check:
    nix flake check

# Home-Manager module evaluation test (impure; see CONTRACT-CHANGE #3)
nix-eval-test:
    nix build --no-link --impure -f nix/tests/hm-eval.nix

# Budgets (docs/BENCH.md) on the real stack: kurashid + frontend in a headless sandbox (rule 9)
bench-gate:
    cargo build --release -p kurashid -p kurashi -p kurashi-mock
    KURASHI_BIN_DIR="${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-target}/release}" python3 tools/bench/measure.py --name frontend-real --daemon real --max-load 1.5 -- frontend/launch.sh
    python3 tools/bench/budget.py tools/bench/results/frontend-real.json

# What grows in an hour of ordinary use (W90; docs/BENCH.md "Soak"): the real stack in the headless sandbox, one round of
# use over and over, each process's memory once a minute → tools/bench/results/soak-<name>.json. Release binaries from
# $KURASHI_BIN_DIR, tools/bench/bin or target/release (measure.py's order). Before a release, on a quiet machine.
soak minutes="60" *ARGS:
    python3 tools/bench/soak.py --minutes {{minutes}} {{ARGS}} -- frontend/launch.sh

# W33 (docs/BENCH.md "2026-10-22"): the textured shell on the real stack, nine scenarios × three runs, medians in
# tools/bench/results/w33-<scenario>.json. Copies the binaries into tools/bench/bin (from $CARGO_TARGET_DIR or target/).
bench-texture:
    cargo build --workspace --release
    mkdir -p tools/bench/bin
    cp "${CARGO_TARGET_DIR:-target}/release/kurashid" "${CARGO_TARGET_DIR:-target}/release/kurashi" "${CARGO_TARGET_DIR:-target}/release/kurashi-mock" tools/bench/bin/
    sh tools/bench/w33.sh

# Golden screenshots of the core surfaces: `just golden` compares, `just golden --update` rewrites tools/golden/ref
golden *ARGS:
    tools/golden/run.sh {{ARGS}}

# Every bundled mod and the test mod `hello` through the real shell, headless (W14): kurashid built with the test-mods
# feature (it links `hello`), then the hello test and the all-mods test. Machine B: KURASHI_RENDER_NODE=/dev/dri/renderD129.
mods-live:
    #!/usr/bin/env bash
    set -uo pipefail
    cargo build -p kurashid --features test-mods || exit 1
    cargo build -p kurashi || exit 1
    status=0
    bash frontend/test-modqml.sh || status=1
    bash frontend/test-mods-live.sh || status=1
    exit "$status"

# The bar's peeks (K35, I67) in the headless sandbox: every bar edge, the weather and sysmon states, reduced motion, the fade,
# the idle Stage (frontend/test-peek.sh; PEEK_PHASES selects phases). Machine B: KURASHI_RENDER_NODE=/dev/dri/renderD129.
peek:
    #!/usr/bin/env bash
    set -uo pipefail
    cargo build -p kurashid -p kurashi -p kurashi-mock || exit 1
    bash frontend/test-peek.sh

# Web dock (K38): the web host against the mock (pages, profiles, privacy net log, memory), then the real daemon end
# to end (pins in the config, host start/scope/stop). Machine B: KURASHI_RENDER_NODE=/dev/dri/renderD129.
webdock:
    #!/usr/bin/env bash
    set -uo pipefail
    cargo build -p kurashi-mock -p kurashid -p kurashi || exit 1
    status=0
    timeout 1200 bash mods/webdock/test/test-host.sh || status=1
    timeout 600 bash mods/webdock/test/test-real.sh || status=1
    timeout 900 bash mods/webdock/test/test-dock.sh || status=1
    timeout 600 bash mods/webdock/test/test-background.sh || status=1
    exit "$status"

# K59: every shader is compiled to the .qsb the frontend loads (Qt 6 shader tools, in nix develop) and committed beside
# its source. K83: vertex shaders too (the motion forms warp a GridMesh), in any folder under frontend/shaders.
shaders:
    #!/usr/bin/env bash
    set -euo pipefail
    find frontend/shaders \( -name '*.frag' -o -name '*.vert' \) -print0 | sort -z | while IFS= read -r -d '' f; do
        qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$f.qsb" "$f"
    done
