#!/usr/bin/env bash
# Install cgg (Rust call-graph generator) from source. No release binaries exist.
# Sentinel: skip if already present. Cross-platform Rust bootstrap (NO curl|sh).
# Only INVOKES brew/apt/rustup — does not manage their lifecycle.
#
# Soft-fail: if a prereq is missing or the build fails, SKIP cgg with a warning
# (exit 0) rather than aborting the whole apply — a missing optional tool must
# never block the rest of the bootstrap. Retries on the next apply.
set -euo pipefail

command -v cgg >/dev/null 2>&1 && { echo "cgg present"; exit 0; }
[ -x "$HOME/.cargo/bin/cgg" ] && { echo "cgg present (~/.cargo/bin)"; exit 0; }

skip() { echo "WARN: skipping cgg — $1 (will retry next apply)."; exit 0; }

ensure_cargo() {
  command -v cargo >/dev/null 2>&1 && return 0
  [ -x "$HOME/.cargo/bin/cargo" ] && { export PATH="$HOME/.cargo/bin:$PATH"; return 0; }
  echo "cargo absent — installing Rust the platform-native way (no curl|sh)…"
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || skip "Homebrew required to install Rust on macOS"
      # Homebrew's `rustup` formula replaced `rustup-init`; it is keg-only.
      brew list rustup >/dev/null 2>&1 || brew install rustup || skip "brew install rustup failed"
      local rustup_prefix; rustup_prefix="$(brew --prefix rustup)/bin"
      export PATH="$rustup_prefix:$PATH"
      rustup default stable || skip "rustup default stable failed"   # install + set default toolchain
      ;;
    Linux)
      command -v apt-get >/dev/null 2>&1 || skip "no apt-get; install Rust manually, then re-apply"
      sudo apt-get update -y || true
      if sudo apt-get install -y rustup 2>/dev/null; then
        rustup default stable || skip "rustup default stable failed"
      else
        sudo apt-get install -y cargo || skip "apt install cargo failed"
      fi
      ;;
    *) skip "unsupported OS $(uname -s)" ;;
  esac
  export PATH="$HOME/.cargo/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || skip "cargo still not on PATH after install"
}

ensure_cargo
echo "installing cgg via 'cargo install --git' (compiles from source — may take a few minutes)…"
cargo install --git https://github.com/NeuralNotwerk/cgg cgg || skip "cargo build failed"
echo "cgg installed: $(command -v cgg || echo "$HOME/.cargo/bin/cgg")"
