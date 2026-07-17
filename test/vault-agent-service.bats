#!/usr/bin/env bats
# Tests for the Vault Agent bring-up script
# (.chezmoiscripts/run_onchange_after_40-vault-agent-service.sh.tmpl).
#
# Regression guard for the silent-config-drift bug: the script's run_onchange
# hash covered ONLY the systemd unit, so an agent.hcl edit (e.g. #68's new
# secrets-static.systemd.env template block) neither re-ran the script nor
# restarted a running agent — new template blocks silently never rendered. The
# script must (a) re-run when agent.hcl / the unit / the plist changes and
# (b) RESTART an already-running agent instead of no-op `enable --now`-ing it.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_40-vault-agent-service.sh.tmpl"

setup() { setup_stub_path; CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"; }

# ----- run_onchange triggers: all three sources must be hash-embedded -----

@test "vault-agent-service: re-runs on systemd unit changes (unit hash embedded)" {
  grep -qF 'include "dot_config/systemd/user/vault-agent.service.tmpl" | sha256sum' "$SCRIPT"
}

@test "vault-agent-service: re-runs on agent.hcl changes (config hash embedded)" {
  grep -qF 'include "dot_config/vault/agent.hcl.tmpl" | sha256sum' "$SCRIPT"
}

@test "vault-agent-service: re-runs on launchd plist changes (plist hash embedded)" {
  grep -qF 'include "Library/LaunchAgents/rocks.stump.vault-agent.plist.tmpl" | sha256sum' "$SCRIPT"
}

# ----- behavior: render the template and run it against stubbed systemctl/launchctl -----

# Render once into a runnable script; the only directives are the sha256sum
# comment hashes. Mirrors the vault-agent-stale.bats render idiom (CI installs
# chezmoi for the bats job).
_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  HOME="$BATS_TEST_TMPDIR" chezmoi execute-template --source "$REPO_ROOT" \
    < "$SCRIPT" > "$BATS_TEST_TMPDIR/svc.sh"
  [ -s "$BATS_TEST_TMPDIR/svc.sh" ]
}

_run_script() {
  run env HOME="${H:-$BATS_TEST_TMPDIR/home}" bash "$BATS_TEST_TMPDIR/svc.sh"
}

@test "linux: RESTARTS an already-running agent (try-restart, not a no-op enable --now)" {
  _render
  make_stub uname 'echo Linux'
  make_stub systemctl "printf 'systemctl %s\n' \"\$*\" >> '$CALLS'; exit 0"  # is-active=0 => running
  _run_script
  [ "$status" -eq 0 ]
  grep -qF -- '--user try-restart vault-agent' "$CALLS"
  run grep -F -- 'enable --now' "$CALLS"
  [ "$status" -eq 1 ]   # grep exits 1 = the no-op enable --now path was NOT taken
}

@test "linux: agent not running => enable --now, no restart" {
  _render
  make_stub uname 'echo Linux'
  make_stub systemctl "printf 'systemctl %s\n' \"\$*\" >> '$CALLS'
[ \"\$2\" = is-active ] && exit 3
exit 0"
  _run_script
  [ "$status" -eq 0 ]
  grep -qF -- '--user enable --now vault-agent' "$CALLS"
  run grep -F 'try-restart' "$CALLS"
  [ "$status" -eq 1 ]   # a stopped agent must not be "restarted" into a double start
}

@test "linux: no user systemd bus => soft-fail (exit 0, WARN, nothing enabled)" {
  _render
  make_stub uname 'echo Linux'
  make_stub systemctl "printf 'systemctl %s\n' \"\$*\" >> '$CALLS'
[ \"\$2\" = daemon-reload ] && exit 1
exit 0"
  _run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"no user systemd bus"* ]]
  run grep -E 'enable|restart' "$CALLS"
  [ "$status" -eq 1 ]   # soft-fail must not touch the unit at all
}

@test "darwin: reloads the LaunchAgent (bootout + bootstrap, the restart recipe)" {
  _render
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/Library/LaunchAgents"
  touch "$H/Library/LaunchAgents/rocks.stump.vault-agent.plist"
  make_stub uname 'echo Darwin'
  make_stub id 'echo 501'
  make_stub launchctl "printf 'launchctl %s\n' \"\$*\" >> '$CALLS'; exit 0"
  _run_script
  [ "$status" -eq 0 ]
  grep -qF 'launchctl bootout gui/501' "$CALLS"
  grep -qF 'launchctl bootstrap gui/501' "$CALLS"
}

@test "darwin: missing plist => skips cleanly without touching launchctl" {
  _render
  H="$BATS_TEST_TMPDIR/home-noplist"; mkdir -p "$H"
  make_stub uname 'echo Darwin'
  make_stub launchctl "printf 'launchctl %s\n' \"\$*\" >> '$CALLS'; exit 0"
  _run_script
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "darwin: bootstrap failure soft-fails with a WARN (no hard exit)" {
  _render
  H="$BATS_TEST_TMPDIR/home-ssh"; mkdir -p "$H/Library/LaunchAgents"
  touch "$H/Library/LaunchAgents/rocks.stump.vault-agent.plist"
  make_stub uname 'echo Darwin'
  make_stub id 'echo 501'
  make_stub launchctl 'exit 1'   # no GUI session: bootout AND bootstrap fail
  _run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}
