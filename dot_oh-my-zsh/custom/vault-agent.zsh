# Control the Vault Agent launchd job that renders secrets from OpenBao.
vault-agent() {
  emulate -L zsh
  local plist="$HOME/Library/LaunchAgents/rocks.stump.vault-agent.plist"
  case "$1" in
    start|load)    launchctl load -w "$plist" && echo "vault-agent loaded" ;;
    stop|unload)   launchctl unload -w "$plist" && echo "vault-agent unloaded" ;;
    restart)       launchctl unload "$plist" 2>/dev/null; launchctl load -w "$plist" && echo "vault-agent restarted" ;;
    status)        launchctl list | grep -E 'rocks\.stump\.vault-agent' || echo "vault-agent: not loaded" ;;
    log)           tail -f "$HOME/.config/vault/agent.log" ;;
    env)           cat "$HOME"/.config/vault/secrets-*.env 2>/dev/null || echo "no rendered secrets yet" ;;
    *) print -u2 "usage: vault-agent {start|stop|restart|status|log|env}"; return 2 ;;
  esac
}
