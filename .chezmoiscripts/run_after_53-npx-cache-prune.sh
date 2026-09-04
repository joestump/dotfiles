#!/usr/bin/env bash
# Prune corrupt npx package-cache entries (~/.npm/_npx) on every apply.
#
# npx runs MCP servers (chrome-devtools-mcp and friends) out of ~/.npm/_npx.
# A partial or clobbered cache install leaves the .bin symlinks dangling and
# every launch fails with "sh: 1: chrome-devtools-mcp: not found" until the
# entry is deleted — npx reinstalls on next use. This script detects entries
# whose bin shims dangle and removes exactly those; healthy entries are
# never touched.
#
# @joestump-agent 09/04/2026 - Added after the chrome-devtools MCP died on a
# corrupt cache entry (build/src/bin missing, package.json gone).

set -euo pipefail

. "$HOME/.config/dotfiles/ui-lib.sh" 2>/dev/null || {
  heading() { printf '\n== %s ==\n' "$*"; }
  item() { shift; echo "    - $*"; }
}

command -v npm >/dev/null 2>&1 || { echo "no npm; skipping npx cache prune"; exit 0; }

cache="$HOME/.npm/_npx"
[ -d "$cache" ] || exit 0

heading "🧹 npx cache"
pruned=0
for entry in "$cache"/*/; do
  [ -d "$entry" ] || continue
  # `find -L ... -type l` is the canonical dangling-symlink probe: with -L the
  # type test resolves the target, and a shim whose target is gone reports as
  # a (broken) link rather than the file it should point at.
  if [ -e "$entry/node_modules/.bin" ] && [ -n "$(find -L "$entry/node_modules/.bin" -type l -print -quit 2>/dev/null)" ]; then
    rm -rf "$entry"
    pruned=$((pruned + 1))
    item ok "pruned corrupt npx cache entry $(basename "$entry")"
  fi
done
if [ "$pruned" -eq 0 ]; then
  item dim "npx cache healthy"
fi
