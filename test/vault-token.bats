#!/usr/bin/env bats
# Tests for custom/vault-token.zsh (export VAULT_TOKEN from the Vault Agent's
# AppRole token) and the agent.hcl.tmpl sink that mirrors that token to
# ~/.vault-token. Together they make bare `vault` commands ride the durable
# machine identity instead of a stale interactive OIDC token (dotfiles#1).
load test_helper

setup() { setup_stub_path; }

# Build a sandbox $HOME with a controllable agent-token, echo its path.
_fakehome() {
  local h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.config/vault"
  printf '%s' "$h"
}

# ----- custom/vault-token.zsh: the VAULT_TOKEN export guard -----

@test "vault-token: exports VAULT_TOKEN from agent-token when unset" {
  local h; h="$(_fakehome)"
  printf 's.testtoken123' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.testtoken123"* ]]
}

@test "vault-token: a preset VAULT_TOKEN is preserved (deliberate override wins)" {
  local h; h="$(_fakehome)"
  printf 's.fromfile' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; export VAULT_TOKEN=s.preset; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "tok=$VAULT_TOKEN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=s.preset"* ]]
}

@test "vault-token: no-op (no error) when agent-token is missing" {
  local h; h="$(_fakehome)"   # dir exists, agent-token does not
  # ${VAULT_TOKEN+SET} is 'SET' only if the var exists — asserts genuinely UNSET,
  # not merely empty, so removing the -s guard (which would export "") is caught.
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "state=[${VAULT_TOKEN+SET}]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=[]"* ]]
}

@test "vault-token: no-op when agent-token is empty (0 bytes)" {
  local h; h="$(_fakehome)"
  : > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "state=[${VAULT_TOKEN+SET}]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=[]"* ]]
}

@test "vault-token: strips a trailing newline from the token file" {
  local h; h="$(_fakehome)"
  printf 's.trailing\n' > "$h/.config/vault/agent-token"
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; echo "len=${#VAULT_TOKEN} tok=[$VAULT_TOKEN]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tok=[s.trailing]"* ]]
  [[ "$output" == *"len=10"* ]]
}

@test "vault-token: VAULT_TOKEN is exported so child processes inherit it" {
  local h; h="$(_fakehome)"
  printf 's.exported' > "$h/.config/vault/agent-token"
  # `env` is a forked child — it only sees VAULT_TOKEN if it was *exported*.
  run zsh -c 'export HOME="'"$h"'"; unset VAULT_TOKEN; source "$REPO_ROOT/dot_oh-my-zsh/custom/vault-token.zsh"; env | grep "^VAULT_TOKEN="'
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAULT_TOKEN=s.exported"* ]]
}

# ----- agent.hcl.tmpl: the ~/.vault-token sink is on the AppRole path only -----

@test "agent.hcl: the AppRole branch mirrors the token to ~/.vault-token" {
  local tmpl="$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  awk '/\{\{ if stat/{f=1;next} /\{\{ else/{f=0} f' "$tmpl" > "$BATS_TEST_TMPDIR/approle.hcl"
  [ -s "$BATS_TEST_TMPDIR/approle.hcl" ]
  run grep -E '^[[:space:]]+path = .*/\.vault-token"' "$BATS_TEST_TMPDIR/approle.hcl"
  [ "$status" -eq 0 ]
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

@test "agent.hcl: renders with the ~/.vault-token sink on this AppRole host" {
  # Real render — only meaningful where chezmoi is present and AppRole is wired
  # (the CI bats job has neither, so it skips; the lint job renders separately).
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  [ -f "$HOME/.config/vault/approle/secret-id" ] || skip "no AppRole secret-id on this host"
  run chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_config/vault/agent.hcl.tmpl"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/rendered.hcl"
  run grep -E '^[[:space:]]+path = .*/\.vault-token"' "$BATS_TEST_TMPDIR/rendered.hcl"
  [ "$status" -eq 0 ]
}
