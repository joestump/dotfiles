#!/usr/bin/env bats
# Tests for mcp_secret in dot_config/dotfiles/mcp-merge-lib.sh. It must read the
# per-user token the Vault Agent injects into ~/.config/vault/secrets-static.env
# (secret/users/$USER/*), NOT query secret/personal/* via the vault CLI. The old
# vault-CLI path was not per-user AND blanked the outline/github/karakeep Bearers
# whenever no vault token was present at merge time (dotfiles OMG 2026-07-05).
load test_helper

LIB="$REPO_ROOT/dot_config/dotfiles/mcp-merge-lib.sh"

# Build a sandbox $HOME with a rendered secrets-static.env; echo its path.
_home_with() {
  local h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.config/vault"
  printf '%s\n' "$@" > "$h/.config/vault/secrets-static.env"
  printf '%s' "$h"
}

@test "mcp_secret returns the env-injected (Vault-Agent-rendered) token" {
  local h; h="$(_home_with 'export OUTLINE_API_TOKEN="tok_from_render"')"
  run bash -c 'export HOME="'"$h"'"; . "'"$LIB"'"; mcp_secret outline OUTLINE_API_TOKEN "fallback"'
  [ "$status" -eq 0 ]
  [ "$output" = "tok_from_render" ]
}

@test "mcp_secret falls back to the live value when the var is absent" {
  local h; h="$(_home_with 'export SOMETHING_ELSE="x"')"
  run bash -c 'export HOME="'"$h"'"; . "'"$LIB"'"; mcp_secret karakeep KARAKEEP_API_KEY "live_fallback"'
  [ "$status" -eq 0 ]
  [ "$output" = "live_fallback" ]
}

@test "mcp_secret does NOT depend on the vault CLI" {
  setup_stub_path
  make_stub vault 'echo "vault must not be called by mcp_secret" >&2; exit 1'
  local h; h="$(_home_with 'export GITHUB_PERSONAL_ACCESS_TOKEN="gh_agent"')"
  run bash -c 'export HOME="'"$h"'"; . "'"$LIB"'"; mcp_secret github GITHUB_PERSONAL_ACCESS_TOKEN "fb"'
  [ "$status" -eq 0 ]
  [ "$output" = "gh_agent" ]
}

@test "the lib no longer runs a vault query for secrets (code, not comments)" {
  # Strip comments, then assert no active `vault kv get` / secret/personal remains.
  run bash -c "grep -vE '^[[:space:]]*#' \"$LIB\" | grep -nE 'vault kv get|secret/personal'"
  [ "$status" -eq 1 ]   # grep exits 1 = no matches
}
