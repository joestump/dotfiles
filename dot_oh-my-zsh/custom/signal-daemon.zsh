# Control the signal-cli daemon that backs the Signal MCP — cross-platform.
#   macOS:  launchd LaunchAgent (rocks.stump.signal-daemon)
#   Linux:  systemd --user service (signal-daemon)
# Runs as you, no sudo. One warm JVM holds the account + a JSON-RPC interface on
# tcp 127.0.0.1:7583; the Signal MCP is a thin client to it. Verbs:
#   start | stop | restart | status | log | ping
# (`ping` checks the JSON-RPC port is listening.)
signal-daemon() {
  emulate -L zsh
  local log="$HOME/.local/share/signal-cli/daemon.log"
  if [[ "$OSTYPE" == darwin* ]]; then
    local plist="$HOME/Library/LaunchAgents/rocks.stump.signal-daemon.plist"
    case "$1" in
      start|load)  launchctl load -w "$plist" && echo "signal-daemon loaded" ;;
      stop|unload) launchctl unload -w "$plist" && echo "signal-daemon unloaded" ;;
      restart)     launchctl unload "$plist" 2>/dev/null; launchctl load -w "$plist" && echo "signal-daemon restarted" ;;
      status)      launchctl list | grep -E 'rocks\.stump\.signal-daemon' || echo "signal-daemon: not loaded" ;;
      log)         tail -f "$log" ;;
      ping)        nc -z 127.0.0.1 7583 && echo "signal-daemon: JSON-RPC up (127.0.0.1:7583)" || echo "signal-daemon: port 7583 not listening" ;;
      *) print -u2 "usage: signal-daemon {start|stop|restart|status|log|ping}"; return 2 ;;
    esac
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    case "$1" in
      start)   systemctl --user enable --now signal-daemon && echo "signal-daemon started" ;;
      stop)    systemctl --user stop signal-daemon && echo "signal-daemon stopped" ;;
      restart) systemctl --user restart signal-daemon && echo "signal-daemon restarted" ;;
      status)  systemctl --user --no-pager status signal-daemon ;;
      log)     journalctl --user -u signal-daemon -f ;;
      ping)    nc -z 127.0.0.1 7583 && echo "signal-daemon: JSON-RPC up (127.0.0.1:7583)" || echo "signal-daemon: port 7583 not listening" ;;
      *) print -u2 "usage: signal-daemon {start|stop|restart|status|log|ping}"; return 2 ;;
    esac
  fi
}
