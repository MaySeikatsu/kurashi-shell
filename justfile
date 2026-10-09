# Kurashi-shell task runner (use inside `nix develop`).

default:
    @just --list

# fmt-check + clippy (deny warnings) + tests
check:
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test --workspace

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
    python3 tools/bench/measure.py --name frontend-real --daemon real -- qs -p frontend
    python3 tools/bench/budget.py tools/bench/results/frontend-real.json
