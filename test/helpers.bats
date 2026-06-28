#!/usr/bin/env bats
# Tests for the zsh OMZ helper files (run through zsh with stubbed commands).
load test_helper

setup() { setup_stub_path; }

@test "all custom zsh files parse (zsh -n)" {
  for f in "$REPO_ROOT"/dot_oh-my-zsh/custom/*.zsh; do
    run zsh -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "vault-agent: bad subcommand prints usage and returns 2" {
  run zsh -c 'source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-agent.zsh"; vault-agent bogus'
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: vault-agent"* ]]
}

@test "vault-agent: status dispatches to launchctl" {
  make_stub launchctl 'echo "LAUNCHCTL $*"'
  run zsh -c 'source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-agent.zsh"; vault-agent status'
  [ "$status" -eq 0 ]
  # stub output has no matching label, so the helper reports "not loaded"
  [[ "$output" == *"not loaded"* ]]
}

@test "vault-oidc-login: local path runs 'vault login -method=oidc'" {
  make_stub vault 'echo "VAULT $*"'
  run zsh -c 'unset SSH_CONNECTION SSH_TTY; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-oidc-login.zsh"; vault-oidc-login'
  [[ "$output" == *"VAULT login -method=oidc"* ]]
}

@test "vault-oidc-login: over SSH prints the tunnel before logging in" {
  make_stub vault 'echo "VAULT $*"'
  run zsh -c 'export SSH_CONNECTION="1 2 3 4"; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-oidc-login.zsh"; vault-oidc-login' </dev/null
  [[ "$output" == *"ssh -L 8250:localhost:8250"* ]]
  [[ "$output" == *"VAULT login -method=oidc"* ]]
}

@test "secrets.zsh: sources rendered secrets-*.env files" {
  local fakehome="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fakehome/.config/vault"
  echo 'export TEST_SECRET=hello' > "$fakehome/.config/vault/secrets-test.env"
  run zsh -c 'export HOME="'"$fakehome"'"; source "$REPO_ROOT/dot_oh-my-zsh/custom/secrets.zsh"; echo "val=$TEST_SECRET"'
  [[ "$output" == *"val=hello"* ]]
}

@test "secrets.zsh: no-op (no error) when nothing is rendered yet" {
  local fakehome="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fakehome/.config/vault"
  run zsh -c 'export HOME="'"$fakehome"'"; source "$REPO_ROOT/dot_oh-my-zsh/custom/secrets.zsh"; echo done'
  [ "$status" -eq 0 ]
  [[ "$output" == *done* ]]
}
