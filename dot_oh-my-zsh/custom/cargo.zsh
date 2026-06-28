# Rust/cargo: cargo-installed binaries (cgg, etc.) + the toolchain on PATH.
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
typeset -U path
path=("$CARGO_HOME/bin" $path)
# macOS: Homebrew's `rustup` is keg-only, so add its bin for `cargo`/`rustc`.
[[ -d /opt/homebrew/opt/rustup/bin ]] && path=("/opt/homebrew/opt/rustup/bin" $path)
