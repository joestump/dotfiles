# Shared UI helpers for chezmoi run scripts (bash/sh) — sourced by the package and
# plugin scripts to turn noisy sections into clean progress.
#
#   • Interactive + gum present  → a gum spinner; the section's output is hidden
#     (shown only if the command FAILS, via --show-error).
#   • Anything else (no TTY, no gum, cron, ssh BatchMode, captured apply) → a quiet
#     "→ title … ok/FAILED" line with output tucked into $UI_LOG.
#
# gum spin emits raw ANSI + leaks output when stdout isn't a TTY, so the TTY guard is
# mandatory — otherwise a captured/cron apply would get garbled. Callers keep their
# own tolerance: `step "…" -- cmd || warn "…"`.
UI_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/chezmoi-apply.log"
mkdir -p "${UI_LOG%/*}" 2>/dev/null || true
have() { command -v "$1" >/dev/null 2>&1; }

step() {
  local title="$1"; shift
  [ "${1:-}" = "--" ] && shift
  if have gum && [ -t 1 ]; then
    gum spin --show-error --spinner minidot --title "$title" -- "$@"
  else
    printf '  → %s … ' "$title"
    if "$@" >>"$UI_LOG" 2>&1; then echo "ok"; else local rc=$?; echo "FAILED (see $UI_LOG)"; return "$rc"; fi
  fi
}

# One-line status (styled via gum log on a TTY, plain otherwise).
say()  { if have gum && [ -t 1 ]; then gum log --level info "$*"; else echo "  $*"; fi; }
warn() { if have gum && [ -t 1 ]; then gum log --level warn "$*"; else echo "  WARN: $*" >&2; fi; }
