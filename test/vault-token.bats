#!/usr/bin/env bats
# Tests for custom/vault-token.zsh — it exposes the personal Vault Agent's AppRole
# token as $VAULT_PERSONAL_TOKEN for opt-in tooling. Per ADR-0038 / SPEC-0022
# "Personal Credential Quarantine" the personal token MUST NOT be exported as
# $VAULT_TOKEN nor mirrored to ~/.vault-token (those are the human OIDC identity).
load test_helper

setup() { setup_stub_path; }

# Build a sandbox $HOME with a controllable agent-token, echo its path.
_fakehome() {
  local h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.config/vault"
  printf '%s' "$h"
}

# ----- custom/vault-token.zsh: the VAULT_PERSONAL_TOKEN export guard -----

@test "vault-token: exports VAULT_PERSONAL_TOKEN from agent-token when unset" {
  local h; h="$(_fakehome)"
  printf 's.testtoken123' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_PERSONAL_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.testtoken123"* ]]
}

@test "vault-token: MUST NOT set VAULT_TOKEN (quarantine — ADR-0038)" {
  local h; h="$(_fakehome)"
  printf 's.personaltoken' > "$h/.config/vault/agent-token"
  # VAULT_TOKEN starts UNSET and must stay genuinely unset — the personal token
  # may never shadow the human OIDC identity.
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "vt=[${VAULT_TOKEN+SET}] vpt=[$VAULT_PERSONAL_TOKEN]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"vt=[]"* ]]
  [[ "$output" == *"vpt=[s.personaltoken]"* ]]
}

@test "vault-token: a preset VAULT_PERSONAL_TOKEN is preserved (deliberate override wins)" {
  local h; h="$(_fakehome)"
  printf 's.fromfile' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; export VAULT_PERSONAL_TOKEN=s.preset; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_PERSONAL_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.preset"* ]]
}

@test "vault-token: does not disturb a preset VAULT_TOKEN (human OIDC session)" {
  local h; h="$(_fakehome)"
  printf 's.personaltoken' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; export VAULT_TOKEN=s.oidcadmin; unset VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "vt=$VAULT_TOKEN vpt=$VAULT_PERSONAL_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"vt=s.oidcadmin"* ]]
  [[ "$output" == *"vpt=s.personaltoken"* ]]
}

@test "vault-token: no-op (no error) when agent-token is missing" {
  local h; h="$(_fakehome)"   # dir exists, agent-token does not
  # ${VAULT_PERSONAL_TOKEN+SET} is 'SET' only if the var exists — asserts genuinely
  # UNSET, not merely empty, so removing the -s guard (which would export "") is caught.
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
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_PERSONAL_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "len=${#VAULT_PERSONAL_TOKEN} tok=[$VAULT_PERSONAL_TOKEN]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=[s.trailing]"* ]]
  [[ "$output" == *"len=10"* ]]
}
