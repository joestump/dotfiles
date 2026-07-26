#!/usr/bin/env bats
# Regression guard for the signal-cli data-dir lock class of failure.
#
# signal-cli takes an EXCLUSIVE lock on ~/.local/share/signal-cli. A second
# instance does not fail — it prints "Config file is in use by another instance,
# waiting…" and blocks forever. Everything below exists because that turned into
# a silent, unbounded hang in `czu`:
#
#   1. a hand-rolled rocks.stump.signal-cli LaunchAgent (KeepAlive, --socket mode)
#      outlived the switch to the managed --tcp daemon and sat blocked for days;
#   2. it grabbed the lock the moment the managed daemon reloaded, so port 7583
#      went dead while `launchctl list` still showed a healthy job;
#   3. czu's recovery ping fell through to a COLD `signal-cli send`, which blocked
#      on that lock with its output sent to /dev/null — czu stopped dead right
#      after "✓ Vault Agent reloaded", and the state file stayed "failed", so
#      every later run walked into the same stall.
load test_helper

NOTIFY="$REPO_ROOT/dot_config/dotfiles/signal-notify.sh.tmpl"
CZU_RUN="$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
DAEMON_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_42-signal-daemon-service.sh.tmpl"
DAEMON_ZSH="$REPO_ROOT/dot_oh-my-zsh/custom/signal-daemon.zsh"

@test "notify: the cold signal-cli fallback is bounded, never bare" {
  # A bare `signal-cli … send` here is the hang. It must go through _signal_bounded.
  run grep -nE '^\s*signal-cli -a "\$SIGNAL_NUMBER" send' "$NOTIFY"
  [ "$status" -ne 0 ]
  grep -q '_signal_bounded [0-9]\+ signal-cli -a "\$SIGNAL_NUMBER" send' "$NOTIFY"
}

@test "notify: _signal_bounded actually kills a command that overruns" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  setup_stub_path
  # Hide any real timeout/gtimeout so this exercises the pure-shell watchdog,
  # which is the path macOS takes (no coreutils by default).
  make_stub timeout  'exit 127'
  make_stub gtimeout 'exit 127'
  local lib="$BATS_TEST_TMPDIR/signal-notify.sh"
  chezmoi execute-template --source "$REPO_ROOT" < "$NOTIFY" > "$lib"
  # command -v finds the stubs, so force _signal_have to report them missing.
  cat >> "$lib" <<'EOF'
_signal_have() { case "$1" in timeout|gtimeout) return 1 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac; }
EOF
  local start finish
  start=$SECONDS
  run bash -c ". '$lib'; _signal_bounded 2 sleep 60"
  finish=$SECONDS
  # Killed, not completed: nonzero rc, and back well inside the sleep's 60s.
  [ "$status" -ne 0 ]
  [ $(( finish - start )) -lt 15 ]
}

@test "czu-run: records success BEFORE the best-effort recovery ping" {
  # Ordering is what stops an interrupted notify from pinning the state at
  # "failed" forever. set_state ok must appear before the notify call.
  local state_line ping_line
  state_line=$(grep -n '^set_state ok' "$CZU_RUN" | tail -1 | cut -d: -f1)
  ping_line=$(grep -n 'notify "✅ czu' "$CZU_RUN" | tail -1 | cut -d: -f1)
  [ -n "$state_line" ]
  [ -n "$ping_line" ]
  [ "$state_line" -lt "$ping_line" ]
}

@test "42-signal-daemon: reaps the legacy rocks.stump.signal-cli LaunchAgent" {
  grep -q 'rocks.stump.signal-cli' "$DAEMON_SCRIPT"
  grep -q 'launchctl bootout "gui/\$(id -u)/rocks.stump.signal-cli"' "$DAEMON_SCRIPT"
}

@test "42-signal-daemon: drains signal-cli before bootstrapping the replacement" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # The drain has to sit BETWEEN bootout and bootstrap, or the new daemon races
  # the dying JVM for the lock and loses silently.
  run python3 - "$DAEMON_SCRIPT" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
out  = s.index('launchctl bootout "gui/$(id -u)" "$plist"')
drain = s.index("pkill -KILL -f 'signal-cli .*daemon'")
boot = s.index('launchctl bootstrap "gui/$(id -u)" "$plist"')
assert out < drain < boot, (out, drain, boot)
PY
  [ "$status" -eq 0 ]
}

@test "42-signal-daemon: verifies port 7583 rather than trusting 'loaded'" {
  grep -q 'nc -z 127.0.0.1 7583' "$DAEMON_SCRIPT"
  grep -q 'not listening' "$DAEMON_SCRIPT"
}

@test "signal-daemon helper: stop and restart drain the lock" {
  grep -q '_signal_daemon_drain()' "$DAEMON_ZSH"
  # Both verbs, or a `restart` still races whatever `stop` left behind.
  grep -qE 'stop\|unload\).*_signal_daemon_drain' "$DAEMON_ZSH"
  grep -qE 'restart\).*_signal_daemon_drain' "$DAEMON_ZSH"
}

@test "signal-daemon helper: the drain pattern cannot match signal-mcp or the log tail" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # pkill -f is blunt: the pattern must hit the daemon and nothing else we run.
  run python3 - <<'PY'
import re
pat = re.compile(r'signal-cli .*daemon')
hit = "/opt/homebrew/bin/signal-cli -a +12065550100 daemon --tcp 127.0.0.1:7583"
misses = [
  "uv run --directory /home/j/src/signal-mcp signal-mcp --transport stdio --channel",
  "tail -f /home/j/.local/share/signal-cli/daemon.log",
  "signal-cli -a +12065550100 link -n laptop",
]
assert pat.search(hit), hit
for m in misses:
    assert not pat.search(m), m
PY
  [ "$status" -eq 0 ]
}

@test "signal-daemon helper: status reports the port, not just the launchd job" {
  # "Loaded" was the misleading signal — the job looked fine for an hour while
  # nothing could reach it.
  grep -q 'port 7583 NOT listening' "$DAEMON_ZSH"
}
