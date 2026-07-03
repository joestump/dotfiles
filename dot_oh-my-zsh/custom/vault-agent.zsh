# Control the Vault Agent that renders OpenBao secrets — cross-platform.
#   macOS:  launchd LaunchAgent (rocks.stump.vault-agent)
#   Linux:  systemd --user service (vault-agent)
# Both run as you, no sudo. Verbs: start | stop | restart | status | log | env
vault-agent() {
  emulate -L zsh
  if [[ "$OSTYPE" == darwin* ]]; then
    local plist="$HOME/Library/LaunchAgents/rocks.stump.vault-agent.plist"
    case "$1" in
      start|load)  launchctl load -w "$plist" && echo "vault-agent loaded" ;;
      stop|unload) launchctl unload -w "$plist" && echo "vault-agent unloaded" ;;
      restart)     launchctl unload "$plist" 2>/dev/null; launchctl load -w "$plist" && echo "vault-agent restarted" ;;
      status)      launchctl list | grep -E 'rocks\.stump\.vault-agent' || echo "vault-agent: not loaded" ;;
      log)         tail -f "$HOME/.config/vault/agent.log" ;;
      env)         cat "$HOME"/.config/vault/secrets-*.env 2>/dev/null || echo "no rendered secrets yet" ;;
      *) print -u2 "usage: vault-agent {start|stop|restart|status|log|env}"; return 2 ;;
    esac
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    case "$1" in
      start)   systemctl --user enable --now vault-agent && echo "vault-agent started" ;;
      stop)    systemctl --user stop vault-agent && echo "vault-agent stopped" ;;
      restart) systemctl --user restart vault-agent && echo "vault-agent restarted" ;;
      status)  systemctl --user --no-pager status vault-agent ;;
      log)     journalctl --user -u vault-agent -f ;;
      env)     cat "$HOME"/.config/vault/secrets-*.env 2>/dev/null || echo "no rendered secrets yet" ;;
      *) print -u2 "usage: vault-agent {start|stop|restart|status|log|env}"; return 2 ;;
    esac
  fi
}

# vsr — vault secrets refresh: re-render OpenBao secrets NOW (skip the ~5-min
# interval) and reload the shell once they're written. `vault-agent restart`
# returns before the render finishes, so we wait for the rendered file to change
# first — otherwise you'd reload onto the PREVIOUS values. Full update = `czu`.
vsr() {
  emulate -L zsh
  zmodload -F zsh/stat b:zstat 2>/dev/null
  local f="$HOME/.config/vault/secrets-static.env"
  local before now i
  before=$(zstat +mtime "$f" 2>/dev/null)
  vault-agent restart || return
  for i in {1..16}; do                       # wait up to ~8s for a fresh render
    now=$(zstat +mtime "$f" 2>/dev/null)
    (( ${now:-0} > ${before:-0} )) && break
    sleep 0.5
  done
  [[ -o interactive ]] && exec zsh
}

# czrefresh — STOPGAP for token_file hosts (pre-AppRole): re-authenticate to
# OpenBao and re-render secrets in one command, instead of remembering the
# `vault login -method=oidc` + `vault-agent restart` incantation. On AppRole
# hosts the agent renews itself, so this just forces a fresh render.
#
# Proactive "your login is about to expire" warnings are handled by the stale-
# secret detector (vault-agent-stale, dotfiles#3), not here.
czrefresh() {
  emulate -L zsh
  if [[ -f "$HOME/.config/vault/approle/secret-id" ]]; then
    print -u2 "ℹ️  This host uses AppRole auth — the agent renews itself, no re-login needed."
    print -u2 "    Forcing a re-render anyway…"
    vsr
    return
  fi
  print -u2 "→ re-authenticating to OpenBao (OIDC) — this is the token_file stopgap."
  print -u2 "  For a permanent fix, provision AppRole:  czapprole --local   (or czapprole <host>)"
  vault-oidc-login && vsr
}
