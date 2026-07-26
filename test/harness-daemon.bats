#!/usr/bin/env bats
# The Go harness daemon (ADR-0005) is the ONLY supervisor for background
# Claude Code / Crush sessions. These tests pin the pieces that make that
# true: the systemd unit + launchd plist exec `harness daemon` with a secrets
# environment and a usable PATH, and the migration script retires every legacy
# mechanism (harnessd.* LaunchAgents, harness@.service units, the standalone
# claude-headless.service, both tmux servers). The seed's own couplings live
# in test/harness.bats.
load test_helper

UNIT="$REPO_ROOT/dot_config/systemd/user/harness.service.tmpl"
PLIST="$REPO_ROOT/Library/LaunchAgents/rocks.stump.harness.plist.tmpl"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_51-harness-daemon-service.sh.tmpl"

_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

@test "harness-daemon: systemd unit execs the run_after_32 build with a usable PATH" {
  # The daemon spawns claude/crush/uv/npx — a bare systemd PATH breaks them.
  grep -Eq '^Environment=PATH=%h/\.local/bin:%h/go/bin' "$UNIT"
  # The binary is the chezmoi build in ~/.local/bin, not a go-install leftover.
  _render "$UNIT" | grep -Eq '^ExecStart=.*/\.local/bin/harness daemon$'
  _render "$UNIT" | grep -Eq '^ExecReload=.*/\.local/bin/harness reload$'
}

@test "harness-daemon: systemd unit loads the Vault secrets (agents inherit them)" {
  # Harnesses inherit the daemon environment; a boot-started unit has no login
  # shell, so the unit must consume the systemd-syntax secrets render. The `-`
  # keeps an unprovisioned box booting.
  grep -Eq '^EnvironmentFile=-%h/\.config/vault/secrets-static\.systemd\.env$' "$UNIT"
}

@test "harness-daemon: launchd plist is valid, sources secrets, execs 'harness daemon'" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  _render "$PLIST" | python3 -c "
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
assert d['Label'] == 'rocks.stump.harness'
cmd = d['ProgramArguments'][-1]
# sh -c wrapper: source the Vault secrets, then exec the run_after_32 build.
assert 'secrets-static.env' in cmd, cmd
assert cmd.rstrip().endswith('/.local/bin/harness daemon'), cmd
assert '.local/bin' in d['EnvironmentVariables']['PATH']
assert d['RunAtLoad'] is True and d['KeepAlive'] is True
"
}

@test "harness-daemon: zsh-harnessd external is gone and its files are retired" {
  ! grep -q 'zsh-harnessd"' "$REPO_ROOT/.chezmoiexternal.toml"
  grep -qF '.oh-my-zsh/custom/plugins/zsh-harnessd' "$REPO_ROOT/.chezmoiremove"
  grep -qF '.local/bin/harness-run' "$REPO_ROOT/.chezmoiremove"
  grep -qF '.local/bin/claude-headless.sh' "$REPO_ROOT/.chezmoiremove"
}

@test "harness-daemon: migration script tears down every legacy mechanism" {
  grep -q 'claude-headless\.service' "$SCRIPT"
  grep -q "harness@" "$SCRIPT"
  grep -q 'harnessd\.\*\.plist' "$SCRIPT"   # macOS LaunchAgent label family
  grep -q 'kill-server' "$SCRIPT"
  grep -q 'ui-lib\.sh' "$SCRIPT"
}

@test "harness-daemon: migration re-starts what was live, under the SEED names" {
  # A live legacy remote-control or Signal arbiter must come back under the
  # daemon as claude-code / crush-signal — not the retired legacy names.
  grep -q 'start claude-code' "$SCRIPT"
  grep -q 'start crush-signal' "$SCRIPT"
  ! grep -q 'start claude-remote-control' "$SCRIPT"
  ! grep -q 'start crush-signal-channel' "$SCRIPT"
}
