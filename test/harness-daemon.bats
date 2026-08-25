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

# --- Daemon restart lifecycle -------------------------------------------------
#
# czu runs `vault-agent restart` every 6h to force a secrets re-render. While
# harness.service declared Requires=vault-agent.service, systemd could not honor
# that without tearing this daemon down first — so every live agent session took
# a SIGTERM four times a day and every scheduled harness re-fired on the way
# back up (harness#266). The unit must want the agent, not require it, and the
# build script must own the restart that a binary upgrade actually needs.

@test "harness-daemon: unit WANTS vault-agent, never REQUIRES it" {
  # Requires= propagates lifecycle. It also never bought what it looked like it
  # bought: it guarantees vault-agent is started, not that it has rendered.
  ! grep -Eq '^Requires=' "$UNIT"
  grep -Eq '^Wants=.*vault-agent\.service' "$UNIT"
  # Ordering is still asserted — After= is what keeps us behind the agent on boot.
  grep -Eq '^After=.*vault-agent\.service' "$UNIT"
}

@test "harness-daemon: build script restarts the daemon only after a successful build" {
  local script="$REPO_ROOT/.chezmoiscripts/run_after_32-install-harness.sh.tmpl"
  # Both success paths (first attempt and the cold-boot retry) restart.
  [ "$(grep -c '^\s*restart_daemon "\$ver"' "$script")" -eq 2 ]
  # It is a no-op when the daemon is not up: run_onchange_after_51 owns starting it.
  grep -q 'systemctl --user is-active --quiet harness.service' "$script"
  grep -q 'launchctl print "gui/\$(id -u)/rocks.stump.harness"' "$script"
  # The up-to-date early exit must come BEFORE any restart, so an apply that
  # rebuilt nothing never bounces a running daemon.
  local uptodate restart
  uptodate="$(grep -n '(up to date)' "$script" | head -1 | cut -d: -f1)"
  restart="$(grep -n 'restart_daemon "\$ver"' "$script" | head -1 | cut -d: -f1)"
  [ "$uptodate" -lt "$restart" ]
}

@test "harness-daemon: czu still RESTARTS the vault agent (reload does not re-render)" {
  # Vault Agent accepts SIGHUP and logs "config reload triggered", but it does
  # not reconcile the rendered secrets file — probed on tars 2026-08-25: a
  # perturbed secrets-static.env was still perturbed 10s after a HUP. Swapping
  # czu to reload would silently stop refreshing secrets, which is the same
  # disease as the `{{ if env ... }}` gating trap this repo already banned.
  # Safe to keep restarting now that harness.service only Wants= the agent.
  grep -q 'vault-agent restart' "$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
}
