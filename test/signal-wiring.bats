#!/usr/bin/env bats
# Locks in the Signal identity wiring across the dotfiles.
#
# The signal-cli daemon and the signal-mcp client share two E.164 identities,
# both provisioned by OpenBao into env vars at apply time:
#
#   SIGNAL_MCP_ACCOUNT   the number the daemon runs AS (signal-cli `-a` and
#                        signal-mcp `--account`). Distinct from the operator on
#                        hosts where the agent has its own number.
#   SIGNAL_MCP_OPERATOR  the human the agent serves (signal-mcp `--operator`).
#
# Both fall back to .signalNumber (Joe's personal number) when the env var is
# absent, so a bare dev box without OpenBao still works (account == operator →
# Note to Self). The allowlists (SIGNAL_MCP_TRUSTED_RECIPIENTS /
# SIGNAL_MCP_TRUSTED_SENDERS) are read by signal-mcp from the env at runtime
# and MUST NOT be rendered as CLI flags.
#
# These tests guard against regressions of:
#   - dotfiles#80 (multi-account mode drop): the daemon MUST keep `-a` pinned
#     to SIGNAL_MCP_ACCOUNT rather than running unscoped multi-account mode,
#     so an unregistered linked device can't degrade healthy accounts.
#   - The earlier `{{ .signalNumber }}` hardcode for `--operator`: that broke
#     the dedicated-agent-number deployment, where account != operator.
load test_helper

SYSTEMD_UNIT="$REPO_ROOT/dot_config/systemd/user/signal-daemon.service.tmpl"
LAUNCHD_PLIST="$REPO_ROOT/Library/LaunchAgents/rocks.stump.signal-daemon.plist.tmpl"
CRUSH_TMPL="$REPO_ROOT/dot_config/crush/crush.json.tmpl"
CODE_MERGE="$REPO_ROOT/.chezmoiscripts/run_after_43-claude-code-mcp-merge.sh.tmpl"
DESKTOP_MERGE="$REPO_ROOT/.chezmoiscripts/run_after_44-claude-desktop-mcp-merge.sh.tmpl"

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
}

# Render a chezmoi template under a controlled env and emit on stdout.
# Args: VAR=value... -- /path/to/template
_render_tmpl() {
  local vars=()
  while [ "$1" != "--" ]; do
    vars+=("$1")
    shift
  done
  shift  # consume --
  local tmpl="$1"
  env -i HOME="$HOME" PATH="$PATH" "${vars[@]}" \
    bash -c 'chezmoi execute-template --source "$0" < "$1"' "$REPO_ROOT" "$tmpl"
}

# ---------------------------------------------------------------------------
# signal-cli daemon: MUST pin `-a` to SIGNAL_MCP_ACCOUNT (NOT multi-account).
# Regression guard for dotfiles#80.
# ---------------------------------------------------------------------------

@test "systemd signal-daemon unit pins -a to SIGNAL_MCP_ACCOUNT (no multi-account)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+353871760709 -- "$SYSTEMD_UNIT"
  [ "$status" -eq 0 ]
  # Explicit `-a` flag is present, scoped to exactly the provisioned account.
  grep -F -- "signal-cli -a +353871760709 daemon" <<<"$output" >/dev/null
  # And no second `-a` / `--account` was injected by env-var expansion.
  ! grep -E -- 'signal-cli -a .* -a ' <<<"$output" >/dev/null
}

@test "systemd signal-daemon -a falls back to .signalNumber without SIGNAL_MCP_ACCOUNT" {
  run _render_tmpl -- "$SYSTEMD_UNIT"
  [ "$status" -eq 0 ]
  # .signalNumber from .chezmoidata.yaml is +12062257886.
  grep -F -- "signal-cli -a +12062257886 daemon" <<<"$output" >/dev/null
}

@test "launchd signal-daemon plist pins -a to SIGNAL_MCP_ACCOUNT (no multi-account)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+353871760709 -- "$LAUNCHD_PLIST"
  [ "$status" -eq 0 ]
  # The plist passes `-a` and the account number as separate <string> elements.
  grep -F -- '<string>-a</string>' <<<"$output" >/dev/null
  grep -F -- '<string>+353871760709</string>' <<<"$output" >/dev/null
}

@test "launchd signal-daemon -a falls back to .signalNumber without SIGNAL_MCP_ACCOUNT" {
  run _render_tmpl -- "$LAUNCHD_PLIST"
  [ "$status" -eq 0 ]
  grep -F -- '<string>-a</string>' <<<"$output" >/dev/null
  grep -F -- '<string>+12062257886</string>' <<<"$output" >/dev/null
}

# ---------------------------------------------------------------------------
# signal-mcp invocation (crush block + claude merge scripts): --operator must
# honor SIGNAL_MCP_OPERATOR, falling back to .signalNumber. The allowlists are
# env-only and MUST NOT appear as flags.
# ---------------------------------------------------------------------------

@test "crush signal block uses SIGNAL_MCP_OPERATOR for --operator when set" {
  run _render_tmpl SIGNAL_MCP_OPERATOR=+15551234567 -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  # Rendered JSON is valid.
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  # --operator receives the env-provided number, not the .signalNumber default.
  grep -F -- '"--operator",' <<<"$output" >/dev/null
  grep -F -- '"+15551234567",' <<<"$output" >/dev/null
}

@test "crush signal block --operator falls back to .signalNumber without SIGNAL_MCP_OPERATOR" {
  run _render_tmpl -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  grep -F -- '"--operator",' <<<"$output" >/dev/null
  grep -F -- '"+12062257886",' <<<"$output" >/dev/null
}

@test "crush signal block --account honors SIGNAL_MCP_ACCOUNT" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+353871760709 SIGNAL_MCP_OPERATOR=+15551234567 -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
sig=d["mcp"]["signal"]
assert "--account" in sig["args"], sig
idx=sig["args"].index("--account")
assert sig["args"][idx+1]=="+353871760709", sig["args"]
assert "--operator" in sig["args"], sig
idx=sig["args"].index("--operator")
assert sig["args"][idx+1]=="+15551234567", sig["args"]
'
}

@test "crush signal block NEVER renders --trusted-recipient flags (env-only)" {
  # The allowlists are read by signal-mcp from the env at runtime; rendering
  # them as CLI flags would shadow the OpenBao-provisioned values.
  run _render_tmpl -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  ! grep -F -- '"--trusted-recipient"' <<<"$output" >/dev/null
  # Even with the env var set, the template must not synthesize flags from it.
  run _render_tmpl SIGNAL_MCP_TRUSTED_RECIPIENTS=+15551234567 -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  ! grep -F -- '"--trusted-recipient"' <<<"$output" >/dev/null
}

@test "claude-code merge script uses SIGNAL_MCP_OPERATOR for --operator" {
  run _render_tmpl SIGNAL_MCP_OPERATOR=+15551234567 -- "$CODE_MERGE"
  [ "$status" -eq 0 ]
  grep -F -- '+15551234567' <<<"$output" >/dev/null
}

@test "claude-desktop merge script uses SIGNAL_MCP_OPERATOR for --operator" {
  run _render_tmpl SIGNAL_MCP_OPERATOR=+15551234567 -- "$DESKTOP_MERGE"
  [ "$status" -eq 0 ]
  grep -F -- '+15551234567' <<<"$output" >/dev/null
}
