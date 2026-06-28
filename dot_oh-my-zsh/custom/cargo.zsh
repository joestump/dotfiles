# Rust/cargo: put cargo-installed binaries (cgg, etc.) on PATH.
# rustup-init is run with --no-modify-path, so PATH wiring lives here.
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
typeset -U path
path=("$CARGO_HOME/bin" $path)
