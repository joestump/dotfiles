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
  run bash -c 'export HOME="'"$h"'"; unset KARAKEEP_API_KEY; . "'"$LIB"'"; mcp_secret karakeep KARAKEEP_API_KEY "live_fallback"'
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

@test "mcp_env returns the env-injected base URL" {
  local h; h="$(_home_with 'export CAIRN_BASE_URL="https://cairn.example"')"
  run bash -c 'export HOME="'"$h"'"; . "'"$LIB"'"; mcp_env CAIRN_BASE_URL "https://stale.example"'
  [ "$status" -eq 0 ]
  [ "$output" = "https://cairn.example" ]
}

@test "mcp_env falls back to the live URL when the var is absent" {
  # A transient OpenBao miss must not blank a working endpoint.
  local h; h="$(_home_with 'export SOMETHING_ELSE="x"')"
  run bash -c 'export HOME="'"$h"'"; unset CAIRN_BASE_URL; . "'"$LIB"'"; mcp_env CAIRN_BASE_URL "https://live.example/mcp"'
  [ "$status" -eq 0 ]
  [ "$output" = "https://live.example/mcp" ]
}

@test "neither cairn nor switchboard hardcodes a host in the merge scripts" {
  # Every half comes from OpenBao — hosts and switchboard's per-client URLs
  # alike. A hostname reappearing here is the regression this guards.
  run grep -nE 'https?://[^ ]*(cairn|switchboard)' \
    "$REPO_ROOT/.chezmoiscripts/run_after_43-claude-code-mcp-merge.sh.tmpl" \
    "$REPO_ROOT/.chezmoiscripts/run_after_44-claude-desktop-mcp-merge.sh.tmpl" \
    "$REPO_ROOT/.chezmoidata.yaml"
  [ "$status" -eq 1 ]   # grep exits 1 = no matches
}

@test "switchboard MCP URLs are per-client env references end to end (no baked slug)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # The /mcp/<slug> path segment is a credential-path minted per user+client.
  # chezmoidata renders identically on every box and identity, so a slug
  # committed there pairs one user's slug with another box's bearer — the
  # #122→#127 ping-pong just flipped whose crush was broken. Both halves,
  # host AND slug, must ride the per-user OpenBao bag:
  #   crush        SWITCHBOARD_CRUSH_URL        (expanded by crush at runtime)
  #   claude code  SWITCHBOARD_CLAUDE_CODE_URL  (baked by run_after_43)
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$REPO_ROOT/dot_config/crush/crush.json.tmpl' | python3 -c '
import json,sys
url = json.load(sys.stdin)[\"mcp\"][\"switchboard\"][\"url\"]
assert url == \"\$SWITCHBOARD_CRUSH_URL\", url
'"
  [ "$status" -eq 0 ]
  # No minted per-client slug may reappear in committed data or templates.
  run grep -nE '/mcp/[a-z0-9-]+-(crush|claude-code)-[0-9a-f]+' \
    "$REPO_ROOT/.chezmoidata.yaml" \
    "$REPO_ROOT/dot_config/crush/crush.json.tmpl" \
    "$REPO_ROOT/.chezmoiscripts/run_after_43-claude-code-mcp-merge.sh.tmpl"
  [ "$status" -eq 1 ]   # grep exits 1 = no matches
  # The claude-code merge reads its per-client URL from the same OpenBao bag.
  grep -q 'SWITCHBOARD_CLAUDE_CODE_URL' \
    "$REPO_ROOT/.chezmoiscripts/run_after_43-claude-code-mcp-merge.sh.tmpl"
}

@test "the lib no longer runs a vault query for secrets (code, not comments)" {
  # Strip comments, then assert no active `vault kv get` / secret/personal remains.
  run bash -c "grep -vE '^[[:space:]]*#' \"$LIB\" | grep -nE 'vault kv get|secret/personal'"
  [ "$status" -eq 1 ]   # grep exits 1 = no matches
}
