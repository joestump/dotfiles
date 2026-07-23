#!/usr/bin/env bats
# Regression guard for private_dot_ssh/private_config — ensures the
# chezmoi-managed ssh config parses cleanly and the ControlMaster /
# RemoteCommand / ProxyJump directives are present and well-formed.
load test_helper

SSH_CONFIG="$REPO_ROOT/private_dot_ssh/private_config"

@test "ssh-config: file exists and is named private_ (mode 0600 after apply)" {
  [ -f "$SSH_CONFIG" ]
  # The private_ prefix tells chezmoi to apply with mode 0600; verify the
  # source filename carries it.
  basename "$(dirname "$SSH_CONFIG")" | grep -q '^private_'
}

@test "ssh-config: github block uses port 443 and ssh.github.com" {
  grep -Eq '^Host github\.com' "$SSH_CONFIG"
  grep -Eq '^\s*Hostname\s+ssh\.github\.com' "$SSH_CONFIG"
  grep -Eq '^\s*Port\s+443' "$SSH_CONFIG"
}

@test "ssh-config: claude-* RemoteCommand is quoted (no bare backslash-space escape)" {
  local rc_line
  rc_line=$(grep 'RemoteCommand' "$SSH_CONFIG")
  [[ "$rc_line" == *'--cmd "'* ]]
  [[ "$rc_line" != *'\\ '* ]]
}

@test "ssh-config: ControlMaster block is present with %C ControlPath" {
  grep -Eq 'ControlMaster\s+auto' "$SSH_CONFIG"
  grep -Eq 'ControlPath\s+.*%C' "$SSH_CONFIG"
  grep -Eq 'ControlPersist\s+10m' "$SSH_CONFIG"
}

@test "ssh-config: ControlMaster rule excludes github.com and claude-*" {
  local cm_host_line
  cm_host_line=$(grep -A0 'ControlMaster' "$SSH_CONFIG" | head -1)
  local host_block
  # The Host line for the multiplexing rule is the line(s) above ControlMaster
  host_block=$(grep -B5 'ControlMaster' "$SSH_CONFIG" | grep '^Host ')
  [[ "$host_block" != *github.com* ]]
  [[ "$host_block" != *claude-\** ]]
}

@test "ssh-config: infra ProxyJump hosts use id_ansible IdentityFile" {
  local count
  count=$(grep -c 'IdentityFile ~/.ssh/id_ansible' "$SSH_CONFIG")
  [ "$count" -ge 3 ]
}

@test "ssh-config: every Host block has a User directive" {
  # Parse out Host / HostName / User groups; every Host block that sets
  # HostName (i.e. a real connect target, not a wildcard rule) must also set
  # User. This catches the "forgot User" class of bug.
  awk '
    /^Host /                { host=$0; has_hostname=0; has_user=0 }
    /Hostname|HostName/     { has_hostname=1 }
    /^[ \t]*User[ \t]/      { has_user=1 }
    /^$/ {
      if (has_hostname && !has_user)
        print "MISSING USER: " host
      host=""; has_hostname=0; has_user=0
    }
    END {
      if (has_hostname && !has_user)
        print "MISSING USER: " host
    }
  ' "$SSH_CONFIG" > "$BATS_TEST_TMPDIR/missing"
  run cat "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ssh-config: ssh -G resolves ControlMaster for an infra host" {
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  run ssh -F "$SSH_CONFIG" -G lir 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"controlmaster auto"* ]]
  [[ "$output" == *"controlpath"* ]]
  [[ "$output" == *"controlpersist 600"* ]]
}

@test "ssh-config: ssh -G does NOT set ControlMaster for github.com" {
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  run ssh -F "$SSH_CONFIG" -G github.com 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" != *"controlmaster auto"* ]]
}
