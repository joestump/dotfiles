#!/usr/bin/env bash
# Install cgg (Rust call-graph generator) from source. No release binaries exist.
# Sentinel: skip if already present. Cross-platform Rust bootstrap (NO curl|sh).
# Only INVOKES brew/apt/rustup — does not manage their lifecycle.
set -euo pipefail

command -v cgg >/dev/null 2>&1 && { echo "cgg present"; exit 0; }
[ -x "$HOME/.cargo/bin/cgg" ] && { echo "cgg present (~/.cargo/bin)"; exit 0; }

ensure_cargo() {
  command -v cargo >/dev/null 2>&1 && return 0
  [ -x "$HOME/.cargo/bin/cargo" ] && { export PATH="$HOME/.cargo/bin:$PATH"; return 0; }
  echo "cargo absent — installing Rust the platform-native way (no curl|sh)…"
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || { echo "ERROR: Homebrew required to install Rust on macOS"; exit 1; }
      # Homebrew's `rustup` formula replaced `rustup-init`; it is keg-only.
      brew list rustup >/dev/null 2>&1 || brew install rustup
      export PATH="$(brew --prefix rustup)/bin:$PATH"
      rustup default stable                  # install + set the default toolchain (creates cargo)
      ;;
    Linux)
      command -v apt-get >/dev/null 2>&1 || { echo "ERROR: no apt-get; install Rust manually, then re-apply"; exit 1; }
      sudo apt-get update -y
      if sudo apt-get install -y rustup 2>/dev/null; then rustup default stable
      else sudo apt-get install -y cargo; fi
      ;;
    *) echo "ERROR: unsupported OS $(uname -s)"; exit 1 ;;
  esac
  export PATH="$HOME/.cargo/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "ERROR: cargo still not on PATH after install"; exit 1; }
}

ensure_cargo
echo "installing cgg via 'cargo install --git' (compiles from source — may take a few minutes)…"
cargo install --git https://github.com/NeuralNotwerk/cgg cgg
echo "cgg installed: $(command -v cgg || echo "$HOME/.cargo/bin/cgg")"
