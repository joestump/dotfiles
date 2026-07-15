# Control the tmux-wrapped headless Crush that arbitrates this machine's
# Signal channel — cross-platform:
#   macOS:  launchd LaunchAgent (rocks.stump.crush-signal-channel)
#   Linux:  systemd --user service (crush-signal-channel)
# Verbs (same shape as signal-daemon / vault-agent):
#   start | stop | restart | status | log | attach
# `attach` opens the live Crush TUI in your terminal — ^b d to detach without
# killing anything. `log` follows the supervisor's log (launchd StandardOut /
# systemd journal), not the tmux buffer.
crush-signal-channel() {
  emulate -L zsh
  if [[ "$OSTYPE" == darwin* ]]; then
    local plist="$HOME/Library/LaunchAgents/rocks.stump.crush-signal-channel.plist"
    local log="$HOME/.local/share/crush-signal-channel/agent.log"
    case "$1" in
      start|load)  launchctl load -w "$plist" && echo "crush-signal-channel loaded" ;;
      stop|unload) launchctl unload -w "$plist" 2>/dev/null; tmux -L crush kill-session -t signal 2>/dev/null; echo "crush-signal-channel unloaded" ;;
      restart)     launchctl unload "$plist" 2>/dev/null; tmux -L crush kill-session -t signal 2>/dev/null; launchctl load -w "$plist" && echo "crush-signal-channel restarted" ;;
      status)      launchctl list | grep -E 'rocks\.stump\.crush-signal-channel' || echo "crush-signal-channel: not loaded"; tmux -L crush has-session -t signal 2>/dev/null && echo "tmux session 'signal' is up" || echo "tmux session 'signal' is down" ;;
      log)         tail -f "$log" ;;
      attach)      tmux -L crush attach -t signal ;;
      *) print -u2 "usage: crush-signal-channel {start|stop|restart|status|log|attach}"; return 2 ;;
    esac
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    case "$1" in
      start)   systemctl --user enable --now crush-signal-channel && echo "crush-signal-channel started" ;;
      stop)    systemctl --user stop crush-signal-channel && echo "crush-signal-channel stopped" ;;
      restart) systemctl --user restart crush-signal-channel && echo "crush-signal-channel restarted" ;;
      status)  systemctl --user --no-pager status crush-signal-channel ;;
      log)     journalctl --user -u crush-signal-channel -f ;;
      attach)  tmux -L crush attach -t signal ;;
      *) print -u2 "usage: crush-signal-channel {start|stop|restart|status|log|attach}"; return 2 ;;
    esac
  fi
}
