#!/usr/bin/env bats
# The scheduled StumpCloud sweep: a headless `claude -p` over ~/src/stumpcloud
# every 6h, agent boxes only. These tests pin what makes the sweep useful and
# safe: the prompt primes context and carries the OMG-at-medium+ and
# always-Signal rules, the units exec claude with that prompt and the secrets
# render (no login shell in the loop), both schedulers agree on 6h, and the
# .chezmoiignore role gate keeps every piece off human logins.
load test_helper

PROMPT="$REPO_ROOT/dot_config/dotfiles/stumpcloud-sweep.prompt.md"
UNIT="$REPO_ROOT/dot_config/systemd/user/stumpcloud-sweep.service.tmpl"
TIMER="$REPO_ROOT/dot_config/systemd/user/stumpcloud-sweep.timer.tmpl"
PLIST="$REPO_ROOT/Library/LaunchAgents/rocks.stump.stumpcloud-sweep.plist.tmpl"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_52-stumpcloud-sweep.sh.tmpl"
IGNORE="$REPO_ROOT/.chezmoiignore"

_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

@test "sweep: prompt primes stumpcloud context and encodes the reporting rules" {
  # Context priming: the monorepo checkout and its ops manifests.
  grep -q 'src/stumpcloud' "$PROMPT"
  grep -q 'CLAUDE-OPS\.md' "$PROMPT"
  # OMGs are filed at medium severity or above, without waiting for an ack.
  grep -qi 'MEDIUM or above' "$PROMPT"
  grep -q 'stumpcloud-omg' "$PROMPT"
  # The operator is ALWAYS messaged on Signal, resolved from env — the repo
  # carries no identity values (see the Identity section of .chezmoidata.yaml).
  grep -q 'ALWAYS' "$PROMPT"
  grep -q '\$SIGNAL_MCP_OPERATOR' "$PROMPT"
  # No baked phone numbers.
  ! grep -Eq '\+[0-9]{7,}' "$PROMPT"
}

@test "sweep: systemd unit execs claude -p with the prompt, secrets, and a usable PATH" {
  grep -Eq '^Environment=PATH=%h/\.local/bin:%h/go/bin' "$UNIT"
  grep -Eq '^EnvironmentFile=-%h/\.config/vault/secrets-static\.systemd\.env$' "$UNIT"
  grep -Eq '^ExecStart=.*claude.*stumpcloud-sweep\.prompt\.md' "$UNIT"
  grep -Eq -- '--dangerously-skip-permissions' "$UNIT"
  # A box without the checkout skips cleanly instead of failing the unit.
  grep -Eq '^ExecCondition=.*src/stumpcloud' "$UNIT"
  grep -Eq '^WorkingDirectory=-%h/src/stumpcloud$' "$UNIT"
  # A wedged sweep dies before the next firing.
  grep -Eq '^TimeoutStartSec=' "$UNIT"
}

@test "sweep: timer fires every 6h and catches up after downtime" {
  grep -Eq '^OnUnitActiveSec=6h$' "$TIMER"
  grep -Eq '^Persistent=true$' "$TIMER"
}

@test "sweep: launchd plist is valid, 6h interval, execs claude with the prompt" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  _render "$PLIST" | python3 -c "
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
assert d['Label'] == 'rocks.stump.stumpcloud-sweep'
cmd = d['ProgramArguments'][-1]
assert 'secrets-static.env' in cmd, cmd
assert '/.local/bin/claude' in cmd, cmd
assert 'stumpcloud-sweep.prompt.md' in cmd, cmd
assert d['StartInterval'] == 21600
assert '.local/bin' in d['EnvironmentVariables']['PATH']
"
}

@test "sweep: role gate keeps the sweep off human logins" {
  # The gate derives the role from agentIdentity/username, same as CLAUDE.md.
  grep -q 'hasSuffix "-agent"' "$IGNORE"
  # Behavioral check with THIS machine's identity: agent logins must NOT
  # ignore the sweep files; human logins MUST.
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  rendered="$(_render "$IGNORE")"
  if [[ "$(whoami)" == *-agent ]]; then
    ! grep -q 'stumpcloud-sweep' <<<"$rendered"
  else
    grep -q 'stumpcloud-sweep\.prompt\.md' <<<"$rendered"
    grep -q 'rocks\.stump\.stumpcloud-sweep\.plist' <<<"$rendered"
  fi
}

@test "sweep: enable script hashes its inputs and enables the right scheduler" {
  # run_onchange_ re-fires when the prompt or a unit changes.
  grep -q 'stumpcloud-sweep.prompt.md" | sha256sum' "$SCRIPT"
  grep -q 'stumpcloud-sweep.service.tmpl" | sha256sum' "$SCRIPT"
  grep -q 'stumpcloud-sweep.timer.tmpl" | sha256sum' "$SCRIPT"
  grep -q 'rocks.stump.stumpcloud-sweep.plist.tmpl" | sha256sum' "$SCRIPT"
  grep -q 'stumpcloud-sweep.timer' "$SCRIPT"
  grep -q 'launchctl bootstrap' "$SCRIPT"
  # Same role gate as the ignore file.
  grep -q 'hasSuffix "-agent"' "$SCRIPT"
}
