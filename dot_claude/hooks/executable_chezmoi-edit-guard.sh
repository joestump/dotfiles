#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit) guard.
#
# When an agent edits a file inside the chezmoi SOURCE tree, inject a reminder to
# finish the dotfiles loop (chezmoi apply -> commit -> push) and drop a per-session
# marker so the Stop guard (chezmoi-commit-guard.sh) knows this session touched it.
#
# Managed by chezmoi: dot_claude/hooks/executable_chezmoi-edit-guard.sh
set -euo pipefail

CHEZMOI_SRC="$HOME/.local/share/chezmoi"

# Never wedge the user: if jq is missing, silently no-op.
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$fp" ] || exit 0

# Resolve to an absolute path for a reliable prefix test.
case "$fp" in
  /*) abs="$fp" ;;
  *)  abs="$(pwd)/$fp" ;;
esac

case "$abs" in
  "$CHEZMOI_SRC"/*)
    sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null || echo nosession)"
    sid="$(printf '%s' "$sid" | tr -cd 'a-zA-Z0-9_-')"
    marker_dir="${TMPDIR:-/tmp}/claude-chezmoi-guard"
    mkdir -p "$marker_dir"
    : > "$marker_dir/$sid"

    rel="${abs#"$CHEZMOI_SRC"/}"
    msg="You just edited a chezmoi SOURCE file (${rel}). Before you end this turn you MUST finish the dotfiles loop, or the repo lands on a dirty branch and the rendered file drifts: (1) run \`chezmoi apply\`, (2) commit in ${CHEZMOI_SRC}, (3) push. This is required by Joe's dotfiles workflow."
    jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
    ;;
  *)
    exit 0
    ;;
esac
