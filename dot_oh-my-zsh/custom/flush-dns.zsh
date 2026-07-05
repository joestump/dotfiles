# flush-dns — clear the macOS DNS resolver cache; optionally confirm a specific
# record is reachable again afterward (for when you've just fixed a DNS record that
# was cached with a stale/wrong answer).
#   flush-dns                 → just flush
#   flush-dns example.com     → flush, then confirm with `ping -c 1 example.com`
#                                (success = the stale cached answer is gone)
# macOS only — dscacheutil/mDNSResponder aren't a thing on Linux. Needs sudo.
flush-dns() {
  emulate -L zsh
  [[ "$OSTYPE" == darwin* ]] || { print -u2 "flush-dns: macOS only"; return 1 }
  local host="${1:-}" was_down=0

  # Silent baseline ping — lets the final message say whether this actually fixed
  # something, vs. the host was already reachable.
  [[ -n "$host" ]] && { ping -c 1 "$host" >/dev/null 2>&1 || was_down=1 }

  if ! sudo dscacheutil -flushcache || ! sudo killall -HUP mDNSResponder; then
    _have gum && gum style --foreground 210 "✗ flush-dns: couldn't flush (sudo denied?)" \
      || print -u2 "flush-dns: couldn't flush (sudo denied?)"
    return 1
  fi

  if [[ -z "$host" ]]; then
    _have gum && gum style --foreground 150 "✓ DNS cache flushed" || print -r -- "DNS cache flushed"
    return 0
  fi

  sleep 1   # give mDNSResponder a beat to come back up before testing
  if ping -c 1 "$host" >/dev/null 2>&1; then
    local msg="✓ DNS cache flushed — ${host} responds"
    (( was_down )) && msg+=" (was unreachable before the flush)"
    _have gum && gum style --foreground 150 "$msg" || print -r -- "$msg"
    return 0
  else
    _have gum && gum style --foreground 210 "✗ DNS cache flushed, but ${host} still isn't responding to ping" \
      || print -u2 "DNS cache flushed, but ${host} still isn't responding to ping"
    return 1
  fi
}
