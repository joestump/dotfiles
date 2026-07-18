#!/usr/bin/env bats
# Tests for the dotfiles#12 blast-radius controls:
#   1. openbao-approle-setup.sh — per-host roles, --cidr binding, and the
#      identity-alias merge (incl. the auto-named-entity guard, the dotfiles#1
#      failure mode).
#   2. czapprole — prefers `vault-agent-<host>`, falls back to the legacy shared
#      role, errors when neither exists.
#   3. agent.hcl.tmpl — the vaultSshKeys gate on the shared-SSH-key render.
# Everything server-side is a stubbed `vault`; no OpenBao is touched.
load test_helper

SETUP_SH="$REPO_ROOT/scripts/openbao-approle-setup.sh"
APPROLE_ZSH="$REPO_ROOT/dot_oh-my-zsh/custom/vault-approle.zsh"

setup() {
  setup_stub_path
  export STUB_LOG="$BATS_TEST_TMPDIR/vault-calls.log"; : > "$STUB_LOG"
  # One stub drives every scenario, steered by env vars:
  #   HOSTROLE_EXISTS / SHAREDROLE_EXISTS — do the role-id reads succeed?
  #   ENTITY_ID — identity/entity/name/<user> lookup result ("" = not found)
  #   LOOKUP_ID — existing alias's entity ("" = no alias yet)
  make_stub vault '
    echo "vault $*" >> "$STUB_LOG"
    case "$1 ${2:-}" in
      "token lookup") exit 0 ;;
      "policy read")  exit 0 ;;
      "auth list")    echo "{\"approle/\":{\"accessor\":\"acc_approle_test\"}}"; exit 0 ;;
    esac
    case "$*" in
      "read -field=role_id auth/approle/role/personal-vault-agent/role-id")
        [ "${SHAREDROLE_EXISTS:-1}" = 1 ] || exit 1; echo "rid-shared" ;;
      "read -field=role_id auth/approle/role/vault-agent-"*)
        [ "${HOSTROLE_EXISTS:-1}" = 1 ] || exit 1; echo "rid-perhost" ;;
      "write -f -field=secret_id auth/approle/role/"*)
        echo "sid-test" ;;
      "write auth/approle/role/"*) : ;;
      "read -format=json identity/entity/name/"*)
        [ -n "${ENTITY_ID:-}" ] || exit 2
        printf "{\"data\":{\"id\":\"%s\"}}\n" "$ENTITY_ID" ;;
      "write -format=json identity/lookup/entity "*)
        if [ -n "${LOOKUP_ID:-}" ]; then printf "{\"data\":{\"id\":\"%s\"}}\n" "$LOOKUP_ID"; else echo "{}"; fi ;;
      "write identity/entity-alias "*) : ;;
    esac
    exit 0'
}

# --- openbao-approle-setup.sh ------------------------------------------------

@test "setup: no args keeps the legacy shared role and never touches identity" {
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  grep -q "write auth/approle/role/personal-vault-agent " "$STUB_LOG"
  run grep "identity/" "$STUB_LOG"
  [ "$status" -eq 1 ]   # no identity API calls in shared mode
}

@test "setup: HOST mints vault-agent-<short> (lowercased, domain stripped) + merges the alias" {
  ENTITY_ID="eid-1" LOOKUP_ID="" run bash "$SETUP_SH" IE01.stump.rocks
  [ "$status" -eq 0 ]
  grep -q "write auth/approle/role/vault-agent-ie01 " "$STUB_LOG"
  grep -q "write identity/entity-alias name=rid-perhost canonical_id=eid-1 mount_accessor=acc_approle_test" "$STUB_LOG"
}

@test "setup: --cidr binds both secret-ids and tokens" {
  ENTITY_ID="eid-1" LOOKUP_ID="" run bash "$SETUP_SH" --cidr 10.0.0.5/32 ie01
  [ "$status" -eq 0 ]
  grep -q "secret_id_bound_cidrs=10.0.0.5/32" "$STUB_LOG"
  grep -q "token_bound_cidrs=10.0.0.5/32" "$STUB_LOG"
}

@test "setup: --cidr without a host is rejected (shared role stays unbound)" {
  run bash "$SETUP_SH" --cidr 10.0.0.5/32
  [ "$status" -eq 2 ]
}

@test "setup: alias already merged into the right entity is a no-op" {
  ENTITY_ID="eid-1" LOOKUP_ID="eid-1" run bash "$SETUP_SH" ie01
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already merged"
  run grep "write identity/entity-alias" "$STUB_LOG"
  [ "$status" -eq 1 ]   # must not re-create the alias
}

@test "setup: alias owned by a DIFFERENT entity hard-fails (auto-named-entity guard)" {
  ENTITY_ID="eid-1" LOOKUP_ID="eid-rogue" run bash "$SETUP_SH" ie01
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "already belongs to entity eid-rogue"
}

@test "setup: missing identity entity refuses to continue" {
  ENTITY_ID="" run bash "$SETUP_SH" ie01
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "entity .* not found"
}

# --- czapprole role selection --------------------------------------------------

# Run czapprole in a sandbox: stubs win the PATH race, HOME is disposable, and the
# follow-on tools it shells out to (chezmoi, vault-agent, hostname) are stubbed.
_czapprole() {
  make_stub chezmoi 'exit 0'
  make_stub vault-agent 'exit 0'
  make_stub hostname 'echo TESTBOX'
  HOME="$BATS_TEST_TMPDIR/home" run zsh -c "source '$APPROLE_ZSH'; czapprole $1"
}

@test "czapprole --local: prefers the per-host role when it exists" {
  mkdir -p "$BATS_TEST_TMPDIR/home"
  HOSTROLE_EXISTS=1 _czapprole --local
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "provisioning with role 'vault-agent-testbox'"
  grep -q "write -f -field=secret_id auth/approle/role/vault-agent-testbox/secret-id" "$STUB_LOG"
  [ -s "$BATS_TEST_TMPDIR/home/.config/vault/approle/secret-id" ]
}

@test "czapprole --local: falls back to the shared role with a warning" {
  mkdir -p "$BATS_TEST_TMPDIR/home"
  HOSTROLE_EXISTS=0 SHAREDROLE_EXISTS=1 _czapprole --local
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "shared legacy role"
  grep -q "write -f -field=secret_id auth/approle/role/personal-vault-agent/secret-id" "$STUB_LOG"
}

@test "czapprole user@host: derives the per-host role from the target hostname" {
  # Neither role exists -> fails BEFORE any ssh, and the error names the derived role.
  HOSTROLE_EXISTS=0 SHAREDROLE_EXISTS=0 _czapprole "joestump@IE01.stump.rocks"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "vault-agent-ie01"
  echo "$output" | grep -q "openbao-approle-setup.sh ie01"
}

# --- agent.hcl.tmpl vaultSshKeys gate -------------------------------------------

_render_agent_hcl() {
  HOME="$1" chezmoi execute-template --source "$REPO_ROOT" \
    < "$REPO_ROOT/dot_config/vault/agent.hcl.tmpl" > "$BATS_TEST_TMPDIR/agent.hcl"
  [ -s "$BATS_TEST_TMPDIR/agent.hcl" ]
}

@test "agent.hcl: ssh-keys template renders by default (vaultSshKeys: true)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  fh="$BATS_TEST_TMPDIR/home-default"; mkdir -p "$fh"
  _render_agent_hcl "$fh"
  # Match the template directive, not the explanatory comment that names the file.
  grep -q 'source.*ssh-keys\.ctmpl' "$BATS_TEST_TMPDIR/agent.hcl"
}

@test "agent.hcl: vaultSshKeys=false in the machine config omits the ssh-keys render" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  fh="$BATS_TEST_TMPDIR/home-nossh"; mkdir -p "$fh/.config/chezmoi"
  printf '[data]\nvaultSshKeys = false\n' > "$fh/.config/chezmoi/chezmoi.toml"
  _render_agent_hcl "$fh"
  run grep 'source.*ssh-keys\.ctmpl' "$BATS_TEST_TMPDIR/agent.hcl"
  [ "$status" -eq 1 ]
  grep -q "SSH keys are NOT rendered" "$BATS_TEST_TMPDIR/agent.hcl"
}
