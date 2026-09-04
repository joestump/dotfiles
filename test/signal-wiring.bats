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

# Same as _render_tmpl, but forces the darwin branch — the counterpart of
# _render_tmpl_linux, so per-OS gates can be asserted from either kind of host.
_render_tmpl_darwin() {
  local vars=()
  while [ "$1" != "--" ]; do
    vars+=("$1")
    shift
  done
  shift  # consume --
  local tmpl="$1"
  env -i HOME="$HOME" PATH="$PATH" "${vars[@]}" \
    bash -c 'chezmoi execute-template --source "$0" --override-data '\''{"chezmoi":{"os":"darwin"}}'\'' < "$1"' "$REPO_ROOT" "$tmpl"
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

@test "crush signal env block carries no self-referential SIGNAL_MCP_* entries" {
  # "SIGNAL_MCP_X": "$SIGNAL_MCP_X" is inert: crush expands $VAR from its OWN
  # environment and appends the result to os.Environ() for the child, so a
  # self-mapping reproduces plain inheritance when the var is set and pins an
  # EMPTY (set-but-blank) value when it is not — strictly worse than letting
  # signal-mcp see the var as unset. Identity rides the runtime env (see the
  # identity-free tests above); this pins the #125 placebo from coming back.
  run _render_tmpl -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
env=json.load(sys.stdin)["mcp"]["signal"].get("env",{})
bad=[k for k in env if k.startswith("SIGNAL_MCP_")]
assert not bad, bad
'
}

@test "crush signal PATH override is darwin-only and linux keeps its inherited PATH" {
  # Config env is appended AFTER os.Environ() and the last duplicate key wins,
  # so a PATH entry REPLACES the child's PATH. The override exists for launchd's
  # thin PATH on macOS; rendered on Linux it would silently swap a sane
  # inherited PATH for a mac-shaped one missing ~/.local/bin.
  run _render_tmpl_darwin -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
path=json.load(sys.stdin)["mcp"]["signal"]["env"]["PATH"]
assert path.split(":")[0].endswith("/.local/bin"), path
assert "/opt/homebrew/bin" in path.split(":"), path
'
  run _render_tmpl_linux -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
sig=json.load(sys.stdin)["mcp"]["signal"]
assert "env" not in sig, sig.get("env")
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

@test "crush signal block wires channel_reply (the fork's reply fallback)" {
  # sendChannelReply in the crush fork is a silent no-op when channel_reply is
  # absent — there is no built-in default and no env fallback, so a render
  # without this block drops every channel turn whose model didn't call a send
  # tool itself. The template shipped without it for weeks; the only thing
  # keeping the Signal bot replying was that the stale on-disk config still
  # carried the block, which is why czu's overwrite prompt could never safely
  # be answered "yes". Assert parsed structure, not text, so formatting is free.
  run _render_tmpl -- "$CRUSH_TMPL"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
reply=d["mcp"]["signal"]["channel_reply"]
assert reply["user"]["tool"] == "send_message_to_user", reply
assert reply["user"]["target_param"] == "user_id", reply
assert reply["group"]["tool"] == "send_message_to_group", reply
assert reply["group"]["target_param"] == "group_id", reply
'
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

# ---------------------------------------------------------------------------
# Branch-aware refresh. Agents develop in ~/src/signal-mcp, so the checkout is
# routinely parked on a work branch — including one whose upstream was deleted
# when its PR merged. That state made `git pull --ff-only` exit 1 ("no such ref
# was fetched") and, while this clone was a chezmoi external, took the ENTIRE
# apply down with it. The script owns the clone now and must skip quietly.
# ---------------------------------------------------------------------------

# Build a fixture: a bare origin + a clone at $1/src/signal-mcp, with `uv`
# stubbed to a no-op so the test stops after the git section.
_signal_mcp_fixture() {
  local fh="$1" origin="$1/origin.git" repo="$1/src/signal-mcp"
  mkdir -p "$fh/src"
  git init --quiet --bare -b main "$origin"
  git clone --quiet "$origin" "$repo" 2>/dev/null
  git -C "$repo" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m init
  git -C "$repo" push --quiet -u origin main 2>/dev/null
  setup_stub_path
  make_stub uv 'exit 0'
  # Record every harness invocation so "did it bounce a consumer?" is answered
  # by what the script actually ran, not by grepping its prose.
  make_stub harness 'printf "%s\n" "$*" >> "$HOME/.harness-calls"; exit 0'
}

# Render the Linux body once and run it under a controlled $HOME.
_run_venv_script() {
  local fh="$1" script="$BATS_TEST_TMPDIR/venv.sh"
  _render_tmpl_linux -- "$VENV_SCRIPT" > "$script"
  HOME="$fh" bash "$script" 2>&1
}

@test "signal-mcp: a branch whose upstream is GONE does not fail the apply" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/gone"; mkdir -p "$fh"
  _signal_mcp_fixture "$fh"
  local repo="$fh/src/signal-mcp"

  # Park it on a PR branch, then delete that branch upstream — the exact state
  # a merged-and-deleted PR leaves behind.
  git -C "$repo" push --quiet -u origin main:feat/merged 2>/dev/null
  git -C "$repo" checkout --quiet -b feat/merged
  git -C "$repo" branch --quiet --set-upstream-to=origin/feat/merged 2>/dev/null
  git -C "$repo" push --quiet origin --delete feat/merged 2>/dev/null

  run _run_venv_script "$fh"
  [ "$status" -eq 0 ]                        # the apply survives — the whole point
  [[ "$output" == *"work branch 'feat/merged'"* ]]
  # And the agent's checkout is untouched: still on their branch.
  [ "$(git -C "$repo" symbolic-ref --short HEAD)" = "feat/merged" ]
}

@test "signal-mcp: a work branch is not fingerprinted and bounces no harness" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/wip"; mkdir -p "$fh"
  _signal_mcp_fixture "$fh"
  git -C "$fh/src/signal-mcp" checkout --quiet -b feat/wip

  run _run_venv_script "$fh"
  [ "$status" -eq 0 ]
  # Every commit an agent makes moves HEAD; fingerprinting it would bounce the
  # live Signal bot onto their WIP mid-conversation.
  [ ! -f "$fh/.config/dotfiles/.signal-mcp-head" ]
  [ ! -f "$fh/.harness-calls" ]
}

@test "signal-mcp: the default branch still refreshes and fingerprints" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/main"; mkdir -p "$fh"
  _signal_mcp_fixture "$fh"

  run _run_venv_script "$fh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"signal-mcp at"* ]]
  [ -f "$fh/.config/dotfiles/.signal-mcp-head" ]
}

# ---------------------------------------------------------------------------
# Cross-identity messaging: joestump <-> joestump-agent over Signal.
#
# Each identity holds its own Signal number (secret/users/<whoami>/signal ->
# SIGNAL_MCP_ACCOUNT) and the two message each other directly. The gates are
# the runtime allowlists signal-mcp reads from env:
#
#   human -> agent send     joestump bag       TRUSTED_RECIPIENTS holds the agent number
#   agent -> human send     joestump-agent bag TRUSTED_RECIPIENTS holds the human number
#   agent accepts inbound   joestump-agent bag TRUSTED_SENDERS holds the human number
#
# The bags live in OpenBao, not this repo, so nothing here can repair drift —
# but the guard turns silent drift (a number dropped from one bag quietly
# kills the cross-identity lane) into a red test on any box with a token.
# Bag values are never printed: failures name the key and direction only.
#
# @joestump-agent 09/04/2026 - Added to lock in the joestump <-> joestump-agent
#   Signal lane; the wiring was correct in OpenBao but nothing guarded it.
# ---------------------------------------------------------------------------

_cross_identity_guard() {
  command -v vault >/dev/null 2>&1 || return 99
  local hjson ajson
  hjson="$(vault kv get -format=json secret/users/joestump/signal 2>/dev/null)" || return 99
  ajson="$(vault kv get -format=json secret/users/joestump-agent/signal 2>/dev/null)" || return 99
  HUMAN_BAG="$hjson" AGENT_BAG="$ajson" python3 - <<'PY'
import json, os, sys

def bag(var):
    d = json.loads(os.environ[var])["data"]["data"]
    return {k: [x.strip() for x in str(v).split(",")] for k, v in d.items()}

human, agent = bag("HUMAN_BAG"), bag("AGENT_BAG")
hnum = human.get("SIGNAL_MCP_OPERATOR", [None])[0]
anum = agent.get("SIGNAL_MCP_ACCOUNT", [None])[0]
fail = []
if not hnum:
    fail.append("joestump bag: SIGNAL_MCP_OPERATOR missing")
if not anum:
    fail.append("joestump-agent bag: SIGNAL_MCP_ACCOUNT missing")
if hnum and anum:
    if hnum not in agent.get("SIGNAL_MCP_TRUSTED_RECIPIENTS", []):
        fail.append("joestump-agent bag: TRUSTED_RECIPIENTS missing the human number (agent -> human sends blocked)")
    if hnum not in agent.get("SIGNAL_MCP_TRUSTED_SENDERS", []):
        fail.append("joestump-agent bag: TRUSTED_SENDERS missing the human number (human -> agent inbound blocked)")
    if anum not in human.get("SIGNAL_MCP_TRUSTED_RECIPIENTS", []):
        fail.append("joestump bag: TRUSTED_RECIPIENTS missing the agent number (human -> agent sends blocked)")
if fail:
    sys.exit("\n".join(fail))
PY
}

@test "OpenBao signal bags allow joestump <-> joestump-agent messaging" {
  run _cross_identity_guard
  case "$status" in
    99) skip "no vault access from this box";;
    0)  : ;;
    *)  fail "$output" ;;
  esac
}
