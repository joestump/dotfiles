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

# Load the Vault-Agent-rendered secrets BEFORE anything else, because several
# templates gate on `env "SOME_API_KEY"` at APPLY time and render a smaller file
# when the var is absent. Interactively that never bites — your login shell has
# already sourced this via ~/.oh-my-zsh/custom/00-secrets.zsh. The scheduled run
# is the problem: launchd's plist carries only PATH + VAULT_ADDR, and the systemd
# unit sets no EnvironmentFile at all, so a 6-hourly czu was applying with an
# empty secret environment. Concretely, that rendered crush.json with
# `"providers": {}` and silently disabled every Crush provider until the next
# interactive apply — which in turn pushed you to paste an API key into Crush's
# TUI, persisting a plaintext secret outside OpenBao.
#
# Sourcing here (not in the plist/unit) keeps ONE fix for both platforms and
# preserves this script's contract that a scheduled run behaves exactly like
# typing `czu`. `set -a` exports what each file defines; the guards make this a
# no-op on a machine Vault Agent hasn't provisioned yet. It runs before the
# PATH/VAULT_ADDR exports below so their ${VAR:-default} precedence still holds.
#
# BOTH files, in the same order oh-my-zsh loads them (00-secrets.zsh, then
# env.zsh), because some vars the templates gate on are DERIVED rather than
# rendered: env.zsh computes OPENAI_DIRECT_API_KEY from the raw OPENAI_API_KEY
# before shadowing OPENAI_API_KEY with the LiteLLM gateway, and aliases
# GITEA_ACCESS_TOKEN from GITEA_TOKEN. Sourcing only the secrets file would still
# have silently dropped Crush's `openai` provider. env.zsh is a pure export file
# (no compinit/bindkey/prompt), so it is safe outside an interactive shell.
if [[ -r "$HOME/.config/vault/secrets-static.env" ]]; then
  set -a
  . "$HOME/.config/vault/secrets-static.env"
  [[ -r "$HOME/.oh-my-zsh/custom/env.zsh" ]] && . "$HOME/.oh-my-zsh/custom/env.zsh"
  set +a
fi

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
. "$HOME/.config/dotfiles/czu-lib.sh" 2>/dev/null \
  || fail "czu-lib.sh missing — run 'chezmoi apply' to reinstall it"
CZU_SRC="$(chezmoi source-path 2>/dev/null || print -r -- "$HOME/.local/share/chezmoi")"
czu_out="$(czu_sync_branch "$CZU_SRC" 2>&1)"; czu_rc=$?
case "$czu_out" in
  pulled)            item ok  "dotfiles — synced from fork" ;;
  skip-local-branch) item dim "dotfiles — branch not on fork yet; nothing to pull" ;;
  stash-conflict)
    fail "git sync: your local edits in $CZU_SRC conflict with what was pulled. The pull SUCCEEDED and your edits are safe in a git stash — run 'git -C $CZU_SRC stash pop' and resolve, or 'git -C $CZU_SRC stash drop' to discard them, then re-run czu." ;;
esac
(( czu_rc == 0 )) \
  || fail "git sync failed ($czu_out) — check for local edits/conflicts in $CZU_SRC"
# Source the vault-rendered env so env-conditional templates (e.g. crush.json
# providers) render populated, not empty, when apply runs outside a login shell.
set -a; [ -r "$HOME/.config/vault/secrets-static.env" ] && . "$HOME/.config/vault/secrets-static.env"; set +a
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
