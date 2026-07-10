# Expose the Vault Agent's personal AppRole token as $VAULT_PERSONAL_TOKEN.
#
# Per ADR-0038 / SPEC-0022 (Vault identity model): the personal AppRole cred is
# QUARANTINED. It must never shadow the operator's admin OIDC identity, so it is
# NOT exported as $VAULT_TOKEN and NOT written to ~/.vault-token (that second agent
# sink was removed in agent.hcl.tmpl). Admin capability comes only from the human's
# Pocket ID/LLDAP group via `vault-oidc-login`, whose token lives in ~/.vault-token
# and now sticks.
#
# So:
#   • bare `vault` / $VAULT_TOKEN  -> your OIDC identity (~/.vault-token), admin if your group grants it
#   • $VAULT_PERSONAL_TOKEN         -> the durable personal AppRole, for tools that
#                                      explicitly want secret/data/users/$USER/* access
#
# The agent still self-renews the personal token to ~/.config/vault/agent-token
# (durability past OIDC max-TTL — the 2026-07-01 fix is preserved), it just no
# longer leaks into interactive/admin scope.
#
# Lives in its own file (not inline in env.zsh) so the guard logic is unit-tested
# in test/vault-token.bats.
vault_personal_token_from_agent() {
  local tok="${HOME}/.config/vault/agent-token"
  [[ -s "$tok" ]] || return 0               # nothing rendered yet — stay quiet
  # $(<file) strips any trailing newline, so consumers never see a malformed token.
  export VAULT_PERSONAL_TOKEN="$(<"$tok")"
}
vault_personal_token_from_agent
