#!/usr/bin/env bats
# Tests for the credential guard around the private claude-personal git-repo
# external in .chezmoiexternal.toml. A git-repo external that can't authenticate
# aborts the ENTIRE `chezmoi apply` (exit 128); the guard skips it on a
# credential-less node so the rest of the apply still lands.
load test_helper

EXTERNAL="$REPO_ROOT/.chezmoiexternal.toml"

# Render .chezmoiexternal.toml under a controlled $HOME; echo stdout.
_render() {
  HOME="$1" chezmoi execute-template --source "$REPO_ROOT" < "$EXTERNAL"
}

@test "chezmoiexternal: claude-personal external is wrapped in a credential guard" {
  # Structural guard (runs without chezmoi): the block must sit behind an
  # `{{ if or (stat …) }}` keyed on the rendered secrets file OR a stored git cred.
  run grep -E 'if or \(stat .*secrets-static\.env.*\(stat .*\.git-credentials' "$EXTERNAL"
  [ "$status" -eq 0 ]
}

@test "chezmoiexternal: a credential-less node OMITS the private external" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/nocreds"; mkdir -p "$fh"
  run _render "$fh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"claude-marketplaces/claude-personal"* ]]
}

@test "chezmoiexternal: a node with ~/.git-credentials INCLUDES the private external" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/creds"; mkdir -p "$fh"; : > "$fh/.git-credentials"
  run _render "$fh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-marketplaces/claude-personal"* ]]
}

@test "chezmoiexternal: a provisioned node (rendered secrets) INCLUDES the private external" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/provisioned"; mkdir -p "$fh/.config/vault"
  : > "$fh/.config/vault/secrets-static.env"
  run _render "$fh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-marketplaces/claude-personal"* ]]
}

@test "chezmoiexternal: rendered output is valid TOML when the external is present" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local fh="$BATS_TEST_TMPDIR/toml"; mkdir -p "$fh"; : > "$fh/.git-credentials"
  run bash -c '_render() { HOME="$1" chezmoi execute-template --source "'"$REPO_ROOT"'" < "'"$EXTERNAL"'"; }; _render "'"$fh"'" | python3 -c "import tomllib,sys; tomllib.load(sys.stdin.buffer)"'
  [ "$status" -eq 0 ]
}
