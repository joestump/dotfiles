# Terminal Mode Hygiene
#
# Full-screen TUIs (crush, harness, vim, htop, anything bubbletea) switch the
# terminal into mouse-reporting mode on startup and switch it back on exit. When
# the process dies without running its exit path — an ssh connection dropped by a
# NAT timeout, a SIGKILL, a panic — the "switch back" never happens and the
# terminal is left reporting. Every subsequent scroll then arrives at zsh as
# literal keystrokes, so the prompt fills with garbage like
# "66;96;23M64;96;23M..." (SGR mouse reports, ESC[< prefix and all) instead of
# scrolling the scrollback.
#
# This resets the modes on every precmd. That is the right hook precisely because
# precmd only fires when zsh owns the terminal — no TUI can be running — so
# there is never a live mouse consumer to stomp on. The cost is one ~40-byte
# write per prompt.
#
# Deliberately NOT reset here: the alternate screen buffer (?1049) and bracketed
# paste (?2004). zle manages bracketed paste itself, and blindly leaving the
# alternate screen can eat output a program legitimately put there. `treset`
# below is the manual nuclear option for those cases.
#
# @joestump-agent 08/25/2026 - Added after an overnight ssh session to tars was
# killed mid-TUI and left the local terminal reporting mouse events. Companion
# to the ServerAliveInterval fix in .chezmoidata.yaml, which addresses the
# dropped connection itself rather than the mess it leaves behind.

_term_reset_input_modes() {
  [[ -t 1 ]] || return 0
  # ?1000 X11 click  ?1002 drag  ?1003 any-motion  ?1004 focus
  # ?1005 UTF-8 ext  ?1006 SGR   ?1015 urxvt ext
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1004l\e[?1005l\e[?1006l\e[?1015l'
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _term_reset_input_modes

# Manual full cleanup, for when a crashed TUI leaves more than the mouse behind
# (stuck on the alternate screen, wrong colours, scroll region pinned). Softer
# than `reset`, which re-runs terminal init and clears the scrollback.
treset() {
  printf '\e[?1049l'   # leave the alternate screen buffer
  printf '\e[?7h'      # re-enable line wrap
  printf '\e[r'        # unpin the scroll region
  printf '\e[0m'       # drop any leftover SGR attributes
  printf '\e[?25h'     # show the cursor
  _term_reset_input_modes
  printf '\e[?2004h'   # hand bracketed paste back to zle
  return 0
}
