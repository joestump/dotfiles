#!/usr/bin/env bash
# Stop guard.
#
# If THIS session edited a chezmoi source file (marker left by chezmoi-edit-guard.sh)
# and the chezmoi tree still has UNCOMMITTED changes, block the stop and tell the
# agent to finish the commit. Only fires for sessions that actually touched the
# source, so unrelated sessions with a dirty tree are never nagged.
#
# Loop-safe: blocks once; if the agent tries to stop again while still dirty
# (stop_hook_active=true), it releases rather than trapping the user. Committed-but-
# unpushed does NOT block (avoids wedging when offline / push is rejected).
#
# Managed by chezmoi: dot_claude/hooks/executable_chezmoi-commit-guard.sh
set -euo pipefail

CHEZMOI_SRC="$HOME/.local/share/chezmoi"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null || echo nosession)"
sid="$(printf '%s' "$sid" | tr -cd 'a-zA-Z0-9_-')"
marker_dir="${TMPDIR:-/tmp}/claude-chezmoi-guard"
marker="$marker_dir/$sid"

# No marker => this session never edited chezmoi source => nothing to enforce.
[ -f "$marker" ] || exit 0

# Uncommitted changes in the source tree?
dirty=""
if git -C "$CHEZMOI_SRC" rev-parse --git-dir >/dev/null 2>&1; then
  dirty="$(git -C "$CHEZMOI_SRC" status --porcelain 2>/dev/null || true)"
fi

# Clean (or not a git repo) => clear the marker and allow the stop.
if [ -z "$dirty" ]; then
  rm -f "$marker"
  exit 0
fi

# Still dirty. If we already blocked once this stop cycle, don't wedge — release.
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [ "$stop_active" = "true" ]; then
  rm -f "$marker"
  printf 'chezmoi source at %s still has uncommitted changes; commit + push manually.\n' "$CHEZMOI_SRC" >&2
  exit 0
fi

branch="$(git -C "$CHEZMOI_SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
reason="This session edited chezmoi source files, but ${CHEZMOI_SRC} is still dirty on branch '${branch}'. Finish the dotfiles loop before stopping: (1) chezmoi apply, (2) git -C ${CHEZMOI_SRC} add -A && git commit, (3) git push. Then stop."
jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
