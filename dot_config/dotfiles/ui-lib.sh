# Shared UI helpers for chezmoi run scripts (bash/sh) — sourced by the package and
# plugin scripts to render each install phase as a heading + a ticked list.
#
#   heading "📦 Homebrew"      section header (gum on a TTY, plain otherwise)
#   item ok|no|dim "name"      a colored list line: ✓ / ✗ / ·  (fast, no subprocess)
#   step "Title" -- cmd…       spinner while cmd runs, then a persistent ✓/✗ tick
#   spin "Title" -- cmd…       spinner while cmd runs, NO tick (a following item list
#                              reports the result) — used for batch installs
#   say / warn "msg"           one-line status
#
# gum spin emits raw ANSI + leaks output when stdout isn't a TTY, so every spinner is
# TTY-guarded; off a TTY, output is tucked into $UI_LOG and we print plain lines.
UI_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/chezmoi-apply.log"
mkdir -p "${UI_LOG%/*}" 2>/dev/null || true
have() { command -v "$1" >/dev/null 2>&1; }

heading() {
  if have gum && [ -t 1 ]; then printf '\n'; gum style --foreground 117 --bold "$*"
  else printf '\n== %s ==\n' "$*"; fi
}

item() {  # item ok|no|dim "text"
  local m="$1"; shift
  local g reset=$'\e[0m' c
  case "$m" in
    ok) g="✓"; c=$'\e[38;5;150m' ;;
    no) g="✗"; c=$'\e[38;5;210m' ;;
    *)  g="·"; c=$'\e[38;5;244m' ;;
  esac
  if [ -t 1 ]; then printf '    %s%s %s%s\n' "$c" "$g" "$*" "$reset"
  else printf '    %s %s\n' "$g" "$*"; fi
}

step() {  # spinner + persistent ✓/✗
  local title="$1"; shift; [ "${1:-}" = "--" ] && shift
  if have gum && [ -t 1 ]; then
    if gum spin --show-error --spinner minidot --title "$title" -- "$@"; then item ok "$title"
    else local rc=$?; item no "$title"; return "$rc"; fi
  else
    printf '  → %s … ' "$title"
    if "$@" >>"$UI_LOG" 2>&1; then echo "ok"; else local rc=$?; echo "FAILED (see $UI_LOG)"; return "$rc"; fi
  fi
}

spin() {  # spinner, NO tick (the item list that follows reports the result)
  local title="$1"; shift; [ "${1:-}" = "--" ] && shift
  if have gum && [ -t 1 ]; then gum spin --show-error --spinner minidot --title "$title" -- "$@"
  else "$@" >>"$UI_LOG" 2>&1; fi
}

say()  { if have gum && [ -t 1 ]; then gum log --level info "$*"; else echo "  $*"; fi; }
warn() { if have gum && [ -t 1 ]; then gum log --level warn "$*"; else echo "  WARN: $*" >&2; fi; }
