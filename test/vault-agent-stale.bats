#!/usr/bin/env bats
# Tests for the vault-agent-stale detector state machine
# (dot_config/vault/vault-agent-stale.sh.tmpl). The detector is transition-based:
# it must Signal-alert exactly ONCE when auth goes DEAD (ok -> stale) or a
# token_file login is about to expire (ok -> expiring), announce recovery ONCE
# (stale -> ok), and stay SILENT while nothing changes. State lives in
# ~/.config/vault/.stale-state.
#
# Regression guard for dotfiles#3 / #4 / #23: a broken transition means either a
# MISSED page (secrets silently frozen at last-good values) or alert spam every
# tick. Neither is observable in production until it bites, so pin it here.
load test_helper

DETECTOR="$REPO_ROOT/dot_config/vault/vault-agent-stale.sh.tmpl"

# Render the chezmoi template once into a runnable script. The only directive is
# {{ .vaultAddr }} (from .chezmoidata.yaml); mirrors the chezmoiexternal.bats
# render idiom. VAULT_ADDR is irrelevant here — every `vault` call is stubbed.
_render_detector() {
  HOME="$BATS_TEST_TMPDIR" chezmoi execute-template --source "$REPO_ROOT" \
    < "$DETECTOR" > "$BATS_TEST_TMPDIR/stale.sh"
  [ -s "$BATS_TEST_TMPDIR/stale.sh" ]
}

# Build a sandbox $HOME: a stub signal-notify.sh whose notify() logs to a file, a
# readable non-empty agent-token sink, and optionally a prior state stamp.
#   $1        prior state ("" = none, detector treats absent stamp as "ok")
#   APPROLE=1 mark an AppRole host (a secret-id file suppresses the token_file
#             expiry warning — AppRole hosts renew themselves)
_setup_home() {
  H="$BATS_TEST_TMPDIR/home"
  mkdir -p "$H/.config/vault" "$H/.config/dotfiles" "$H/.local/bin"
  NOTIFY_LOG="$H/notify.log"; : > "$NOTIFY_LOG"
  cat > "$H/.config/dotfiles/signal-notify.sh" <<EOF
notify() { printf '%s\n' "\$*" >> "$NOTIFY_LOG"; }
EOF
  printf 's.sometoken\n' > "$H/.config/vault/agent-token"
  [ -n "${1:-}" ] && printf '%s' "$1" > "$H/.config/vault/.stale-state"
  if [ "${APPROLE:-0}" = 1 ]; then
    mkdir -p "$H/.config/vault/approle"
    printf 'sid\n' > "$H/.config/vault/approle/secret-id"
  fi
  return 0
}

# The detector re-exports PATH with $HOME/.local/bin FIRST, so stubs must land
# there (not the shared STUB_BIN) to win over the system binaries it re-adds.
_stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$H/.local/bin/$1"
  chmod +x "$H/.local/bin/$1"
}

# Force the Linux agent-running path so the test is identical on macOS + Linux CI:
# stub uname -> Linux and systemctl is-active -> success. This isolates the OS-
# agnostic state machine, which is what #23 asks to cover.
_agent_up() {
  _stub uname 'case "${1:-}" in -m) echo x86_64;; *) echo Linux;; esac'
  _stub systemctl 'exit 0'
}

_run_detector() {
  run env HOME="$H" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" bash "$BATS_TEST_TMPDIR/stale.sh"
}

_state() { cat "$H/.config/vault/.stale-state" 2>/dev/null || echo "<none>"; }

@test "ok -> stale: pages once and records 'stale' when auth is DEAD" {
  _render_detector; _setup_home ""; _agent_up
  _stub vault 'exit 1'                       # token lookup fails => auth dead
  _run_detector
  [ "$status" -eq 0 ]
  [ "$(_state)" = "stale" ]
  grep -q "auth is DEAD" "$NOTIFY_LOG"
}

@test "stale -> stale: no re-alert while it stays dead" {
  _render_detector; _setup_home "stale"; _agent_up
  _stub vault 'exit 1'
  _run_detector
  [ "$status" -eq 0 ]
  [ "$(_state)" = "stale" ]
  [ ! -s "$NOTIFY_LOG" ]                     # silent — no duplicate page
}

@test "stale -> ok: announces recovery once when auth is restored" {
  APPROLE=1 _setup_home "stale"; _render_detector; _agent_up
  _stub vault 'echo "{\"data\":{\"ttl\":3600}}"'   # lookup succeeds
  _run_detector
  [ "$status" -eq 0 ]
  [ "$(_state)" = "ok" ]
  grep -q "authentication restored" "$NOTIFY_LOG"
}

@test "ok -> ok: stays silent while healthy" {
  APPROLE=1 _setup_home ""; _render_detector; _agent_up
  _stub vault 'echo "{\"data\":{\"ttl\":3600}}"'
  _run_detector
  [ "$status" -eq 0 ]
  [ ! -s "$NOTIFY_LOG" ]
}

@test "ok -> expiring: warns once when a token_file login is nearly expired" {
  _render_detector; _setup_home ""; _agent_up   # no approle => token_file host
  _stub vault 'echo "{\"data\":{\"ttl\":600}}"'
  _stub python3 'echo 600'                        # detector parses ttl via python3
  _run_detector
  [ "$status" -eq 0 ]
  [ "$(_state)" = "expiring" ]
  grep -q "expires in" "$NOTIFY_LOG"
}

@test "agent not running: exits quietly without touching state" {
  _render_detector; _setup_home "ok"
  _stub uname 'echo Linux'
  _stub systemctl 'exit 3'                        # is-active => not running
  _run_detector
  [ "$status" -eq 0 ]
  [ "$(_state)" = "ok" ]
  [ ! -s "$NOTIFY_LOG" ]
}
