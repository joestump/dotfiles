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
CZU_SRC="$(chezmoi source-path 2>/dev/null || print -r -- "$HOME/src/dotfiles")"
czu_out="$(czu_sync_branch "$CZU_SRC" 2>&1)"; czu_rc=$?
case "$czu_out" in
  pulled)            item ok  "dotfiles — synced from fork" ;;
  skip-local-branch) item dim "dotfiles — branch not on fork yet; nothing to pull" ;;
  stash-conflict)
    fail "git sync: your local edits in $CZU_SRC conflict with what was pulled. The pull SUCCEEDED and your edits are safe in a git stash — run 'git -C $CZU_SRC stash pop' and resolve, or 'git -C $CZU_SRC stash drop' to discard them, then re-run czu." ;;
esac
if (( czu_rc != 0 )) && [[ "$czu_out" == nonff ]]; then
  # By far the most common cause: this box is parked on a feature branch that was
  # merged upstream through a fork PR, so origin's copy was rewritten and the two
  # histories diverged. Nothing is wrong with the local tree — it is just finished
  # work. Say that, instead of "check for local edits/conflicts", which sends you
  # hunting for a dirty file that isn't there.
  _czu_br="$(git -C "$CZU_SRC" symbolic-ref --quiet --short HEAD 2>/dev/null || print -r -- '?')"
  fail "git sync: '$_czu_br' has diverged from origin/$_czu_br and cannot fast-forward, so NOTHING WAS APPLIED. If that branch is already merged, 'git -C $CZU_SRC checkout main && git -C $CZU_SRC pull --ff-only' and re-run czu. Otherwise rebase it onto origin/main."
fi
(( czu_rc == 0 )) \
  || fail "git sync failed ($czu_out) — check for local edits/conflicts in $CZU_SRC"

# Advisory only — czu still applies. czu_sync_branch reports success both when a
# feature branch has nothing to pull and when it fast-forwards from its own stale
# counterpart, so neither outcome says anything about how far the tree has fallen
# behind main. Without this, a box parked on a feature branch renders $HOME from
# that branch forever, silently. See czu_branch_drift in czu-lib.sh.
czu_drift="$(czu_branch_drift "$CZU_SRC" 2>/dev/null)"
czu_drift_parts=(${(s.:.)czu_drift})
case "$czu_drift" in
  current)
    item ok "dotfiles — on main, current" ;;
  behind:*)
    warn "dotfiles — main is ${czu_drift_parts[2]} commits behind origin/main; applying anyway" ;;
  off-main:*)
    if (( ${czu_drift_parts[3]:-0} > 0 )); then
      warn "dotfiles — applying from branch '${czu_drift_parts[2]}', ${czu_drift_parts[3]} commits BEHIND origin/main. Your \$HOME is being rendered from a stale tree; switch to main once this work is merged."
    else
      item dim "dotfiles — on branch '${czu_drift_parts[2]}' (level with origin/main)"
    fi ;;
  detached)
    warn "dotfiles — detached HEAD; applying from an unnamed commit" ;;
esac

# Source the vault-rendered env so env-conditional templates (e.g. crush.json
# providers) render populated, not empty, when apply runs outside a login shell.
set -a; [ -r "$HOME/.config/vault/secrets-static.env" ] && . "$HOME/.config/vault/secrets-static.env"; set +a
# secrets-static.env alone is NOT enough: env.zsh DERIVES vars from it — e.g.
# OPENAI_DIRECT_API_KEY is computed from the raw OpenAI key before the LiteLLM
# shadow repoints OPENAI_API_KEY. Skip this and a scheduled apply renders
# crush.json WITHOUT the openai provider, then the next interactive apply puts
# it back — the file ping-pongs every 6h and czu always looks dirty.
[ -r "$HOME/.oh-my-zsh/custom/env.zsh" ] && . "$HOME/.oh-my-zsh/custom/env.zsh"
chezmoi apply "$@" \
  || fail "chezmoi apply failed — see ~/.cache/chezmoi-apply.log"

heading "🔐 Secrets"
if (( ${+functions[vault-agent]} )) && vault-agent restart >/dev/null 2>&1; then
  item ok "Vault Agent reloaded"
else
  item no "Vault Agent — check 'vault-agent status'"
fi

# Record success BEFORE the recovery ping, not after. The ping is best-effort —
# it reaches out to signal-cli — while the state file is the thing that decides
# whether the NEXT run pings at all. With the old order, anything that made
# notify hang (a wedged signal-cli holding its data-dir lock) and got Ctrl-C'd
# left the state at "failed", so every subsequent czu walked back into the same
# stall. State first means a run that got this far is recorded as the success it
# was, whatever the notification does. notify itself is bounded (signal-notify.sh).
was_failed=0   # not `local` — this is script scope, not a function
[[ "$(get_state)" == "failed" ]] && was_failed=1
set_state ok
(( was_failed )) && notify "✅ czu on ${HOST_SHORT}: back to normal — sync succeeded."
true
