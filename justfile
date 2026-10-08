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
