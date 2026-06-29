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
