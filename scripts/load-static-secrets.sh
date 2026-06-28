#!/usr/bin/env bash
# Load the STATIC secrets currently in your environment into OpenBao KV at the
# paths the Vault Agent reads (secret/personal/*). Contains NO secret values —
# only variable names + paths, so it is safe to commit.
#
# AWS is intentionally NOT here — it becomes a DYNAMIC secret (see
# scripts/openbao-aws-setup.sh).
#
# Run from a shell where the old ~/.zprofile is still sourced, after login:
#     export VAULT_ADDR=https://vault.stump.rocks
#     vault login -method=oidc
#     ~/.local/share/chezmoi/scripts/load-static-secrets.sh
set -euo pipefail

: "${VAULT_ADDR:?export VAULT_ADDR=https://vault.stump.rocks first}"
command -v vault >/dev/null || { echo "vault CLI not found"; exit 1; }
vault token lookup >/dev/null 2>&1 || { echo "Not authenticated. Run: vault login -method=oidc"; exit 1; }

req() {
  local missing=0
  for v in "$@"; do
    [ -n "${!v:-}" ] || { echo "Missing \$$v — is the old ~/.zprofile sourced in this shell?"; missing=1; }
  done
  [ "$missing" -eq 0 ] || exit 1
}

req OPENAI_API_KEY LITELLM_API_KEY GEMINI_API_KEY \
    GITEA_TOKEN POCKETID_API_KEY GARAGE_ACCESS_KEY GARAGE_SECRET_KEY

vault kv put secret/personal/llm \
  OPENAI_API_KEY="$OPENAI_API_KEY" \
  LITELLM_API_KEY="$LITELLM_API_KEY" \
  GEMINI_API_KEY="$GEMINI_API_KEY"

vault kv put secret/personal/gitea    GITEA_TOKEN="$GITEA_TOKEN"
vault kv put secret/personal/pocketid POCKETID_API_KEY="$POCKETID_API_KEY"

vault kv put secret/personal/garage \
  GARAGE_ACCESS_KEY="$GARAGE_ACCESS_KEY" \
  GARAGE_SECRET_KEY="$GARAGE_SECRET_KEY"

echo "✅ Static secrets loaded into OpenBao KV (secret/personal/*)."
echo "   The Vault Agent will render them to ~/.config/vault/secrets-static.env."
