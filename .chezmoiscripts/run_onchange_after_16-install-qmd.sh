#!/usr/bin/env bash
# Install qmd (@tobilu/qmd) — all-local hybrid search CLI.
# Sentinel: skip if present. Verify Node >= 22 (do NOT install Node).
# Do NOT pre-warm the ~2GB GGUF models — first use handles that.
set -euo pipefail

command -v qmd >/dev/null 2>&1 && { echo "qmd present"; exit 0; }

# Soft-fail: if a prereq is missing, SKIP qmd (exit 0) so the rest of the apply
# still runs. It re-installs on the next apply once the prereq is satisfied — a
# missing optional tool must never abort the whole bootstrap.
if ! command -v node >/dev/null 2>&1; then
  echo "WARN: skipping qmd — Node is absent. Will retry on the next apply once Node is present."
  exit 0
fi
NODE_MAJOR="$(node -v | sed 's/^v//; s/\..*//')"
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 22 ]; then
  echo "WARN: skipping qmd — needs Node >= 22 (found: $(node -v 2>/dev/null || echo none)). Will retry on the next apply once Node is present."
  exit 0
fi

# sqlite with loadable-extension support (qmd's vec extension needs it). Invoke
# the platform package manager; do not manage its lifecycle.
case "$(uname -s)" in
  Darwin) command -v brew >/dev/null 2>&1 && { brew list sqlite >/dev/null 2>&1 || brew install sqlite; } ;;
  Linux)  command -v apt-get >/dev/null 2>&1 && { sudo apt-get install -y sqlite3 libsqlite3-dev || true; } ;;
esac

# macOS (Homebrew) has a user-writable global prefix; Linux (NodeSource) puts the
# global prefix under /usr/lib and needs root — fall back to sudo there. Soft-fail
# so a transient npm/network error doesn't abort the rest of the apply.
npm install -g @tobilu/qmd || sudo npm install -g @tobilu/qmd || {
  echo "WARN: qmd npm install failed; will retry on the next apply."; exit 0; }
echo "qmd installed. NOTE: ~2GB GGUF models download to ~/.cache/qmd/ on first use (not pre-warmed here)."
