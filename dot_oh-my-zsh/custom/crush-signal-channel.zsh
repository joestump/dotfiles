# Control the tmux-wrapped headless Crush that arbitrates the agent's Signal
# channel — Linux only (the service is a systemd --user unit; there is no
# macOS launchd counterpart because this agent lives on the M920x).
#   start | stop | restart | status | log | attach
# `attach` opens the live Crush TUI in your terminal (^b d to detach without
# killing anything). `log` follows the systemd journal, not the tmux buffer.
crush-signal-channel() {
  emulate -L zsh
  if [[ "$OSTYPE" == darwin* ]]; then
    print -u2 "crush-signal-channel: agent-only (Linux); no-op on macOS."
    return 2
  fi
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
}
