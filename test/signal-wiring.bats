#!/usr/bin/env bats
# Locks in the Signal identity wiring across the dotfiles.
#
# The signal-cli daemon and the signal-mcp client share two E.164 identities,
# both provisioned by OpenBao into env vars at apply time:
#
#   SIGNAL_MCP_ACCOUNT   the number the signal-mcp CLIENT identifies as
#                        (signal-mcp `--account`). Distinct from the operator on
#                        hosts where the agent has its own number.
#   SIGNAL_MCP_OPERATOR  the human the agent serves (signal-mcp `--operator`).
#
# Both fall back to .signalNumber (Joe's personal number) when the env var is
# absent, so a bare dev box without OpenBao still works (account == operator →
# Note to Self). The allowlists (SIGNAL_MCP_TRUSTED_RECIPIENTS /
# SIGNAL_MCP_TRUSTED_SENDERS) are read by signal-mcp from the env at runtime
# and MUST NOT be rendered as CLI flags.
#
# signal-cli DAEMON design: the daemon runs in MULTI-ACCOUNT mode (no `-a`
# flag) so it serves every linked account and a single unregistered account
# (e.g. an expired linked device) only logs a warning instead of crash-looping
# the daemon for the healthy accounts too. This deliberately reverts the `-a`
# pin from #86: the 2026-07-18 tars incident (200+ restarts after a linked
# device was deactivated remotely) showed the single-account pin is a
# crash-loop footgun, so the daemon stays multi-account.
#
# These tests guard against regressions of:
#   - The multi-account daemon design: the systemd unit and launchd plist MUST
#     NOT render `-a` (multi-account mode), so an unregistered linked device
#     can't crash-loop the daemon for healthy accounts.
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

# Same as _render_tmpl, but forces the Linux branch of {{ if eq .chezmoi.os }}
# gates. The signal-mcp venv script is Linux-only and its tests must see the
# full script body regardless of the host running `make test`.
_render_tmpl_linux() {
  local vars=()
  while [ "$1" != "--" ]; do
    vars+=("$1")
    shift
  done
  shift  # consume --
  local tmpl="$1"
  env -i HOME="$HOME" PATH="$PATH" "${vars[@]}" \
    bash -c 'chezmoi execute-template --source "$0" --override-data '\''{"chezmoi":{"os":"linux"}}'\'' < "$1"' "$REPO_ROOT" "$tmpl"
}

# ---------------------------------------------------------------------------
# signal-cli daemon: MUST run in MULTI-ACCOUNT mode (no `-a` flag). A single
# pinned account crash-loops the daemon when that account is unregistered
# (2026-07-18 tars incident); multi-account mode degrades it to a warning.
# ---------------------------------------------------------------------------

@test "systemd signal-daemon unit runs in multi-account mode (no -a flag)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+15550001111 -- "$SYSTEMD_UNIT"
  [ "$status" -eq 0 ]
  # The daemon must NOT pin `-a` to a single account, even when SIGNAL_MCP_ACCOUNT
  # is set (the env var is for the signal-mcp client, not the daemon).
  ! grep -E -- 'signal-cli(\s+\S+)*\s+-a\s' <<<"$output" >/dev/null
  ! grep -F -- 'signal-cli -a' <<<"$output" >/dev/null
  # The daemon line still launches signal-cli daemon.
  grep -F -- 'signal-cli daemon' <<<"$output" >/dev/null
}

@test "launchd signal-daemon plist runs in multi-account mode (no -a flag)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+15550001111 -- "$LAUNCHD_PLIST"
  [ "$status" -eq 0 ]
  # No `-a` <string> element in the ProgramArguments array, even with the env
  # var set — the daemon serves all linked accounts.
  ! grep -F -- '<string>-a</string>' <<<"$output" >/dev/null
  ! grep -F -- '<string>+15550001111</string>' <<<"$output" >/dev/null
  # The plist still launches the daemon subcommand.
  grep -F -- '<string>daemon</string>' <<<"$output" >/dev/null
}

# ---------------------------------------------------------------------------
# signal-mcp invocation (crush block + claude merge scripts): identity comes
# from the RUNTIME env (SIGNAL_MCP_ACCOUNT / _OPERATOR / _PREFIX, provisioned
# per-user by OpenBao — secret/users/<whoami>/signal), so rendered configs
# carry NO identity at all: no numbers, no account/operator/prefix flags. The
# one exception is the Claude Desktop merge: a GUI app inherits no shell env,
# so run_after_44 bakes the env values at apply time — env-only, no committed
# fallback.
# ---------------------------------------------------------------------------

@test "crush signal block renders identity-free (no account/operator/prefix flags)" {
  run _render_tmpl -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
args=d["mcp"]["signal"]["args"]
assert "--channel" in args, args
for flag in ("--account","--operator","--prefix"):
    assert flag not in args, args
'
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "crush signal block stays identity-free even when SIGNAL_MCP_* env is set" {
  # The env vars are for signal-mcp at RUNTIME; the template must never bake
  # them into the render, or one identity's numbers reach every box.
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+15550001111 SIGNAL_MCP_OPERATOR=+15550002222 SIGNAL_MCP_PREFIX=cc -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
  ! grep -F -- '"--prefix"' <<<"$output" >/dev/null
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

@test "claude-code merge script renders identity-free (runtime env resolves it)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+15550001111 SIGNAL_MCP_OPERATOR=+15550002222 -- "$CODE_MERGE"
  [ "$status" -eq 0 ]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "claude-desktop merge script bakes the env values (GUI app, no shell env)" {
  run _render_tmpl SIGNAL_MCP_ACCOUNT=+15550001111 SIGNAL_MCP_OPERATOR=+15550002222 -- "$DESKTOP_MERGE"
  [ "$status" -eq 0 ]
  grep -F -- '+15550001111' <<<"$output" >/dev/null
  grep -F -- '+15550002222' <<<"$output" >/dev/null
}

# ---------------------------------------------------------------------------
# signal-mcp venv script: pulling to HEAD is not enough — a running harness
# keeps the OLD signal-mcp process (CHANNEL_INSTRUCTIONS is read once at MCP
# initialize), so a HEAD change must bounce the running signal harnesses.
# ---------------------------------------------------------------------------

VENV_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_45-signal-mcp-venv.sh.tmpl"

@test "signal-mcp script fingerprints HEAD and restarts via the harness daemon" {
  run _render_tmpl_linux -- "$VENV_SCRIPT"
  [ "$status" -eq 0 ]
  # Fingerprint across applies — restart exactly once per upstream change.
  [[ "$output" == *'.signal-mcp-head'* ]]
  [[ "$output" == *'harness restart'* ]]
}

@test "signal-mcp restart targets only RUNNING harnesses matched by name" {
  run _render_tmpl_linux -- "$VENV_SCRIPT"
  [ "$status" -eq 0 ]
  # Names are create_-seeded and differ per box (crush-signal vs
  # crush-signal-channel) — must match by substring, never a hardcoded name.
  [[ "$output" == *'"state") == "running"'* ]]
  [[ "$output" == *'"signal" in h.get("name"'* ]]
  [[ "$output" != *'harness restart crush-signal'* ]]
}

@test "signal-mcp first run records the fingerprint without restarting" {
  run _render_tmpl_linux -- "$VENV_SCRIPT"
  [ "$status" -eq 0 ]
  # No baseline to compare against — bouncing a possibly-mid-conversation
  # agent for no code change is worse than waiting one cycle.
  [[ "$output" == *'restart on next change'* ]]
}
