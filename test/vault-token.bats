#!/usr/bin/env bats
# Tests for custom/vault-token.zsh and agent.hcl.tmpl under the ADR-0038 /
# SPEC-0022 Vault identity model: the personal AppRole token is QUARANTINED —
# exported only as $VAULT_PERSONAL_TOKEN, never as $VAULT_TOKEN, and the agent no
# longer mirrors it to ~/.vault-token. That keeps it from shadowing the operator's
# admin OIDC identity (which lives in ~/.vault-token via `vault-oidc-login`).
load test_helper

setup() { setup_stub_path; }

# Build a sandbox $HOME with a controllable agent-token, echo its path.
_fakehome() {
  local h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.config/vault"
  printf '%s' "$h"
}

# ----- custom/vault-token.zsh: exports VAULT_PERSONAL_TOKEN, never VAULT_TOKEN -----

@test "vault-token: exports VAULT_PERSONAL_TOKEN from agent-token" {
  local h; h="$(_fakehome)"
  printf 's.testtoken123' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_PERSONAL_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.testtoken123"* ]]
}

@test "vault-token: NEVER exports VAULT_TOKEN (must not shadow admin OIDC)" {
  local h; h="$(_fakehome)"
  printf 's.testtoken123' > "$h/.config/vault/agent-token"
  # ${VAULT_TOKEN+SET} is 'SET' only if the var exists — asserts genuinely UNSET.
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "state=[${VAULT_TOKEN+SET}]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=[]"* ]]
}

@test "vault-token: leaves a preset VAULT_TOKEN (OIDC admin) untouched" {
  local h; h="$(_fakehome)"
  printf 's.fromfile' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; export VAULT_TOKEN=s.oidcadmin; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.oidcadmin"* ]]
}

@test "vault-token: no-op (no error) when agent-token is missing" {
  local h; h="$(_fakehome)"   # dir exists, agent-token does not
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "state=[${VAULT_PERSONAL_TOKEN+SET}]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=[]"* ]]
}

@test "vault-token: no-op when agent-token is empty (0 bytes)" {
  local h; h="$(_fakehome)"
  : > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "state=[${VAULT_PERSONAL_TOKEN+SET}]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=[]"* ]]
}

@test "vault-token: strips a trailing newline from the token file" {
  local h; h="$(_fakehome)"
  printf 's.trailing\n' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "len=${#VAULT_PERSONAL_TOKEN} tok=[$VAULT_PERSONAL_TOKEN]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=[s.trailing]"* ]]
  [[ "$output" == *"len=10"* ]]
}

@test "vault-token: VAULT_PERSONAL_TOKEN is exported so child processes inherit it" {
  local h; h="$(_fakehome)"
  printf 's.exported' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; env | grep "^VAULT_PERSONAL_TOKEN="'
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAULT_PERSONAL_TOKEN=s.exported"* ]]
}

# ----- agent.hcl.tmpl: neither branch mirrors the token to ~/.vault-token -----

@test "agent.hcl: the AppRole branch does NOT mirror the token to ~/.vault-token" {
  # ADR-0038: the personal token is quarantined to ~/.config/vault/agent-token so
  # it can't shadow the operator's OIDC login in ~/.vault-token.
  local tmpl="$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  awk '/\{\{ if stat/{f=1;next} /\{\{ else/{f=0} f' "$tmpl" > "$BATS_TEST_TMPDIR/approle.hcl"
  [ -s "$BATS_TEST_TMPDIR/approle.hcl" ]
  run grep -E '^[[:space:]]+path = .*/\.vault-token"' "$BATS_TEST_TMPDIR/approle.hcl"
  [ "$status" -ne 0 ]
}

@test "agent.hcl: the legacy token_file branch has NO ~/.vault-token sink" {
  # That path authenticates FROM ~/.vault-token (token_file_path); a sink writing
  # the same file would be circular, so the mirror must not appear there.
  local tmpl="$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  awk '/\{\{ else/{f=1;next} /\{\{ end/{f=0} f' "$tmpl" > "$BATS_TEST_TMPDIR/legacy.hcl"
  [ -s "$BATS_TEST_TMPDIR/legacy.hcl" ]
  run grep -E '^[[:space:]]+path = .*/\.vault-token"' "$BATS_TEST_TMPDIR/legacy.hcl"
  [ "$status" -ne 0 ]
}

@test "agent.hcl: both branches keep the agent-token sink" {
  local tmpl="$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  awk '/\{\{ if stat/{f=1;next} /\{\{ else/{f=0} f' "$tmpl" > "$BATS_TEST_TMPDIR/approle.hcl"
  awk '/\{\{ else/{f=1;next} /\{\{ end/{f=0} f'   "$tmpl" > "$BATS_TEST_TMPDIR/legacy.hcl"
  run grep -E '^[[:space:]]+path = .*/agent-token"' "$BATS_TEST_TMPDIR/approle.hcl"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]+path = .*/agent-token"' "$BATS_TEST_TMPDIR/legacy.hcl"
  [ "$status" -eq 0 ]
}

@test "agent.hcl: renders WITHOUT a ~/.vault-token sink on this AppRole host" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  [ -f "$HOME/.config/vault/approle/secret-id" ] || skip "no AppRole secret-id on this host"
  run chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/rendered.hcl"
  run grep -E '^[[:space:]]+path = .*/\.vault-token"' "$BATS_TEST_TMPDIR/rendered.hcl"
  [ "$status" -ne 0 ]
}
