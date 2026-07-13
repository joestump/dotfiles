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

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
ensure_vault_auth   # SSH-aware: prints tunnel guidance if you're remote + unauthed

req() {
  local missing=0
  for v in "$@"; do
    [ -n "${!v:-}" ] || { echo "Missing \$$v — is the old ~/.zprofile sourced in this shell?"; missing=1; }
  done
  [ "$missing" -eq 0 ] || exit 1
}

req OPENAI_API_KEY LITELLM_API_KEY GEMINI_API_KEY \
    GITEA_TOKEN POCKETID_API_KEY GARAGE_ACCESS_KEY GARAGE_SECRET_KEY

# Feed values over stdin JSON to avoid exposing secrets in argv (dotfiles#11).
vault kv put secret/personal/llm - <<EOF
{"OPENAI_API_KEY":"$OPENAI_API_KEY","LITELLM_API_KEY":"$LITELLM_API_KEY","GEMINI_API_KEY":"$GEMINI_API_KEY"}
EOF

vault kv put secret/personal/gitea    - <<<"{\"GITEA_TOKEN\":\"$GITEA_TOKEN\"}"
vault kv put secret/personal/pocketid - <<<"{\"POCKETID_API_KEY\":\"$POCKETID_API_KEY\"}"

vault kv put secret/personal/garage - <<EOF
{"GARAGE_ACCESS_KEY":"$GARAGE_ACCESS_KEY","GARAGE_SECRET_KEY":"$GARAGE_SECRET_KEY"}
EOF

echo "✅ Static secrets loaded into OpenBao KV (secret/personal/*)."
echo "   The Vault Agent will render them to ~/.config/vault/secrets-static.env."
