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
(( ${+functions[czu_sync_prod]} )) \
  || fail "czu-lib.sh is stale (no czu_sync_prod) — run 'chezmoi apply' to update it"

# Two checkouts, two roles (see czu-lib.sh): czu renders $HOME from the
# PRODUCTION clone — chezmoi's default source dir — which czu_sync_prod keeps
# on clean upstream main. The workbench at ~/src/dotfiles is where development
# happens and czu deliberately never touches it; work reaches this box only by
# merging upstream. --source is passed explicitly everywhere below, so this
# flow also SELF-MIGRATES a box whose rendered chezmoi.toml still points at
# the old shared checkout: the first apply from production rewrites that
# config, and every later chezmoi command agrees by default.
CZU_PROD="${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi"
CZU_DEV="$HOME/src/dotfiles"

# URL for a first-time clone, read from the workbench's origin remote if one
# exists (identity-free — no owner hardcoded here). Boxes bootstrapped by
# czinit already cloned production directly and never hit this path.
czu_url=""
[[ -d "$CZU_DEV/.git" ]] && czu_url="$(git -C "$CZU_DEV" remote get-url origin 2>/dev/null)"

czu_out="$(czu_sync_prod "$CZU_PROD" "$czu_url" 2>&1)"
case "$czu_out" in
  cloned)  item ok  "dotfiles — production clone created at ${CZU_PROD/#$HOME/~}" ;;
  synced)  item ok  "dotfiles — synced to origin/main" ;;
  current) item ok  "dotfiles — current with origin/main" ;;
  offline) warn "dotfiles — no network; applying last-synced main" ;;
  dirty)
    fail "production clone at $CZU_PROD has uncommitted edits. Production is never edited directly — move the change to the workbench ($CZU_DEV), then discard it here (git -C $CZU_PROD checkout -- . ; git -C $CZU_PROD clean -fd) and re-run czu." ;;
  wedged)
    fail "production clone at $CZU_PROD is not on main and could not switch back. It is disposable: inspect with 'git -C $CZU_PROD status', then 'git -C $CZU_PROD switch -f main' — or delete the directory and re-run czu to re-clone." ;;
  nonff)
    fail "production clone has commits origin/main lacks — someone committed in production (work belongs in $CZU_DEV) or upstream main was rewritten. If those commits matter, move them to the workbench FIRST; then 'git -C $CZU_PROD reset --hard origin/main' and re-run czu." ;;
  clone-failed)
    fail "no production clone at $CZU_PROD and could not create one${czu_url:+ from $czu_url}. Clone the dotfiles repo there manually and re-run czu." ;;
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

# Reassert app-rewritten declarative targets BEFORE the main apply. Crush
# rewrites its own ~/.config/crush/crush.json (config migrations, TUI
# actions), which trips chezmoi's changed-since-last-write guard from then
# on: an interactive czu PROMPTS on every run, and the scheduled (no-TTY)
# apply silently skips the file — either way the render stops landing. The
# targets listed here are fully declarative (runtime state lives in the app's
# own data config), so czu_reassert_targets overwrites them scoped and
# unprompted; the main apply below then finds them clean. Failure here is
# advisory — the main apply is the authoritative error path.
czu_reassert_out="$(czu_reassert_targets "$CZU_PROD" "$HOME/.config/crush/crush.json")"
for czu_reassert_line in ${(f)czu_reassert_out}; do
  case "$czu_reassert_line" in
    reasserted:*) item dim "${czu_reassert_line#reasserted:$HOME/} — an app had rewritten it; render reasserted" ;;
    failed:*)     warn "could not reassert ${czu_reassert_line#failed:} — the main apply will report why" ;;
  esac
done

chezmoi apply --source "$CZU_PROD" "$@" \
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
