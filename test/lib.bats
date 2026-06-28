#!/usr/bin/env bats
# Tests for scripts/lib.sh (the SSH-aware vault auth helpers).
load test_helper

setup() { setup_stub_path; }

@test "is_ssh: true when SSH_CONNECTION is set" {
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; export SSH_CONNECTION="1 2 3 4"; is_ssh'
  [ "$status" -eq 0 ]
}

@test "is_ssh: false when no SSH env" {
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; unset SSH_CONNECTION SSH_TTY; is_ssh'
  [ "$status" -eq 1 ]
}

@test "vault_addr_default: defaults to the OpenBao URL when unset" {
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; unset VAULT_ADDR; vault_addr_default; echo "$VAULT_ADDR"'
  [ "$output" = "https://vault.stump.rocks" ]
}

@test "vault_addr_default: preserves an existing VAULT_ADDR" {
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; export VAULT_ADDR=https://example; vault_addr_default; echo "$VAULT_ADDR"'
  [ "$output" = "https://example" ]
}

@test "print_tunnel_hint: shows the SSH -L tunnel and the vault-login shortcut" {
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; print_tunnel_hint 8250'
  [[ "$output" == *"ssh -L 8250:localhost:8250"* ]]
  [[ "$output" == *"vault-login"* ]]
}

@test "ensure_vault_auth: returns 0 when the token is valid" {
  make_stub vault 'exit 0'
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; ensure_vault_auth; echo OK'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "ensure_vault_auth: local + unauthed -> exits 1 with login hint" {
  make_stub vault 'exit 1'
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; unset SSH_CONNECTION SSH_TTY; ensure_vault_auth'
  [ "$status" -eq 1 ]
  [[ "$output" == *"vault login -method=oidc"* ]]
}

@test "ensure_vault_auth: over SSH + unauthed -> prints tunnel guidance" {
  make_stub vault 'exit 1'
  run bash -c '. "$REPO_ROOT/scripts/lib.sh"; export SSH_CONNECTION="1 2 3 4"; ensure_vault_auth'
  [ "$status" -eq 1 ]
  [[ "$output" == *"ssh -L 8250:localhost:8250"* ]]
}

@test "all setup scripts pass bash -n" {
  for f in "$REPO_ROOT"/scripts/*.sh; do
    run bash -n "$f"
    [ "$status" -eq 0 ]
  done
}
