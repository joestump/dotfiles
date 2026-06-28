#!/usr/bin/env bash
# Install qmd (@tobilu/qmd) — all-local hybrid search CLI.
# Sentinel: skip if present. Verify Node >= 22 (do NOT install Node).
# Do NOT pre-warm the ~2GB GGUF models — first use handles that.
set -euo pipefail

command -v qmd >/dev/null 2>&1 && { echo "qmd present"; exit 0; }

NODE_MAJOR="$(node -v 2>/dev/null | sed 's/^v//; s/\..*//')"
{ [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge 22 ]; } || {
  echo "ERROR: qmd needs Node >= 22 (found: $(node -v 2>/dev/null || echo none)). Install/upgrade Node, then re-apply."; exit 1; }

# sqlite with loadable-extension support (qmd's vec extension needs it). Invoke
# the platform package manager; do not manage its lifecycle.
case "$(uname -s)" in
  Darwin) command -v brew >/dev/null 2>&1 && { brew list sqlite >/dev/null 2>&1 || brew install sqlite; } ;;
  Linux)  command -v apt-get >/dev/null 2>&1 && { sudo apt-get install -y sqlite3 libsqlite3-dev || true; } ;;
esac

npm install -g @tobilu/qmd
echo "qmd installed. NOTE: ~2GB GGUF models download to ~/.cache/qmd/ on first use (not pre-warmed here)."
