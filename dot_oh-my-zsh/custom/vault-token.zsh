# Point the vault CLI (and any tool that reads $VAULT_TOKEN) at the Vault Agent's
# self-renewing AppRole token.
#
# The Agent authenticates via AppRole and sinks its token to
# ~/.config/vault/agent-token, but the vault CLI reads $VAULT_TOKEN then
# ~/.vault-token — which otherwise holds a stale interactive OIDC token. Exporting
# it here means bare `vault` commands ride the durable machine identity instead of
# a token that dies at max-TTL (dotfiles#1 follow-up; agent.hcl also mirrors the
# token to ~/.vault-token via a second sink, for tools that read the file).
#
# Lives in its own file (not inline in env.zsh) so the guard logic is unit-tested
# in test/vault-token.bats. Guarded so it never clobbers a deliberate choice:
#   • VAULT_TOKEN already set  -> leave it (e.g. a full-OIDC session you set up)
#   • agent-token missing/empty -> no-op (fresh node before the Agent has authed)
vault_token_from_agent() {
  local tok="${HOME}/.config/vault/agent-token"
  [[ -n "${VAULT_TOKEN:-}" ]] && return 0   # a preset token wins (deliberate override)
  [[ -s "$tok" ]] || return 0               # nothing rendered yet — stay quiet
  # $(<file) strips any trailing newline, so the CLI never sees a malformed token.
  export VAULT_TOKEN="$(<"$tok")"
}
vault_token_from_agent
