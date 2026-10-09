# Kurashi-shell task runner (use inside `nix develop`).

default:
    @just --list

# fmt-check + clippy (deny warnings) + tests
check:
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test --workspace
    sh frontend/test-launch.sh

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

nix-check:
    nix flake check

# Home-Manager module evaluation test (impure; see CONTRACT-CHANGE #3)
nix-eval-test:
    nix build --no-link --impure -f nix/tests/hm-eval.nix

# Budgets (docs/BENCH.md) on the real stack: kurashid + frontend in a headless sandbox (rule 9)
bench-gate:
    python3 tools/bench/measure.py --name frontend-real --daemon real -- frontend/launch.sh
    python3 tools/bench/budget.py tools/bench/results/frontend-real.json

# Golden screenshots of the core surfaces: `just golden` compares, `just golden --update` rewrites tools/golden/ref
golden *ARGS:
    tools/golden/run.sh {{ARGS}}

# Every bundled mod and the test mod `hello` through the real shell, headless (W14): kurashid built with the test-mods
# feature (it links `hello`), then the hello test and the all-mods test. Machine B: KURASHI_RENDER_NODE=/dev/dri/renderD129.
mods-live:
    cargo build -p kurashid --features test-mods
    cargo build -p kurashi
    bash frontend/test-modqml.sh
    bash frontend/test-mods-live.sh
