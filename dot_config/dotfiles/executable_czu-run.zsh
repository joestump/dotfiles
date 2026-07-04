#!/usr/bin/env zsh
# czu-run.sh — the actual sync + apply + secrets logic behind `czu`. Called by:
#   - the `czu` zsh function (interactive — wraps this, then `exec zsh` on success)
#   - the scheduled czu timer/launchd job (every 6h, no TTY, no exec)
# One implementation means the scheduled run behaves exactly like typing `czu`
# yourself. Extra args pass through to `chezmoi apply` (e.g. --refresh-externals).
#
# Failure alerting is TRANSITION-based (mirrors vault-agent-stale): Signal-pings
# once when a run first fails, once when it next succeeds — never every tick, so a
# broken box doesn't spam every 6h. State lives in ~/.cache/czu-scheduled-state.
emulate -L zsh

export PATH="$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export VAULT_ADDR="${VAULT_ADDR:-https://vault.stump.rocks}"

. "$HOME/.config/dotfiles/ui-lib.sh" 2>/dev/null || {
  have() { command -v "$1" >/dev/null 2>&1 }
  heading() { print -r -- ""; print -r -- "== $* ==" }
  item() { shift; print -r -- "    - $*" }
  step() { local t="$1"; shift; [[ "$1" == "--" ]] && shift; "$@" }
  warn() { print -u2 -- "  WARN: $*" }
}
. "$HOME/.config/dotfiles/signal-notify.sh" 2>/dev/null || notify() { logger -t czu -- "$1" 2>/dev/null; true }
. "$HOME/.oh-my-zsh/custom/vault-agent.zsh" 2>/dev/null    # for the `vault-agent` function

HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
STATE_FILE="$HOME/.cache/czu-scheduled-state"   # holds: ok | failed
get_state() { [[ -r "$STATE_FILE" ]] && cat "$STATE_FILE" || print ok }
set_state() { print -rn -- "$1" >| "$STATE_FILE" }

fail() {
  warn "$1"
  if [[ "$(get_state)" != "failed" ]]; then
    notify "🚨 czu on ${HOST_SHORT}: $1"
    set_state failed
  fi
  exit 1
}

have gum && [[ -t 1 ]] && gum style --foreground 213 --bold "⟳ czu · updating ${HOST_SHORT}"

heading "📥 Sync"
step "dotfiles" -- chezmoi git pull -- --ff-only \
  || fail "git pull failed — check for local edits/conflicts in ~/.local/share/chezmoi"
chezmoi apply "$@" \
  || fail "chezmoi apply failed — see ~/.cache/chezmoi-apply.log"

heading "🔐 Secrets"
if (( ${+functions[vault-agent]} )) && vault-agent restart >/dev/null 2>&1; then
  item ok "Vault Agent reloaded"
else
  item no "Vault Agent — check 'vault-agent status'"
fi

if [[ "$(get_state)" == "failed" ]]; then
  notify "✅ czu on ${HOST_SHORT}: back to normal — sync succeeded."
fi
set_state ok
