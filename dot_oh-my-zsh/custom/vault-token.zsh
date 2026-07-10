# Expose the personal Vault Agent's self-renewing AppRole token as
# $VAULT_PERSONAL_TOKEN for opt-in tooling that wants personal-secret access.
#
# ADR-0038 / SPEC-0022 "Personal Credential Quarantine": the personal AppRole token
# is scoped to secret/data/users/<user>/* and MUST NOT shadow the human identity. It
# is therefore NOT exported as $VAULT_TOKEN and NOT mirrored to ~/.vault-token — both
# of those belong to the human OIDC admin token from `vault-oidc-login`. (Exporting it
# as $VAULT_TOKEN was the 2026-07-07 admin-shadowing OMG.) Tools that specifically want
# the personal subtree read $VAULT_PERSONAL_TOKEN explicitly.
#
# Lives in its own file (not inline in env.zsh) so the guard logic is unit-tested in
# test/vault-token.bats. Guards:
#   • VAULT_PERSONAL_TOKEN already set -> leave it (deliberate override)
#   • agent-token missing/empty        -> no-op (fresh node before the Agent has authed)
vault_personal_token_from_agent() {
  local tok="${HOME}/.config/vault/agent-token"
  [[ -n "${VAULT_PERSONAL_TOKEN:-}" ]] && return 0   # a preset value wins (deliberate override)
  [[ -s "$tok" ]] || return 0                        # nothing rendered yet — stay quiet
  # $(<file) strips any trailing newline, so tools never see a malformed token.
  export VAULT_PERSONAL_TOKEN="$(<"$tok")"
}
vault_personal_token_from_agent
