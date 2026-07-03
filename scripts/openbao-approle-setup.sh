#!/usr/bin/env bash
# openbao-approle-setup.sh — SERVER-SIDE, run ONCE as an OpenBao admin.
#
# Gives the personal Vault Agent a machine identity it can renew FOREVER without a
# human. Replaces the old `token_file` auto-auth (an OIDC-seeded token that died at
# max-TTL — see OMG 2026-07-01 / dotfiles#1). AppRole tokens are periodic (renew
# indefinitely) and the secret_id never expires, so the agent re-authenticates on
# its own for the life of the machine.
#
# Idempotent: re-running just rewrites the policy + role to these values. It does
# NOT mint a secret_id — that is per-host and handed out by `czapprole <host>` /
# `czinit` from your authenticated laptop session.
#
#   export VAULT_ADDR=https://vault.stump.rocks
#   vault login -method=oidc          # admin
#   ~/.local/share/chezmoi/scripts/openbao-approle-setup.sh
#
# Prints the role_id at the end (role_id is NOT a secret on its own — it needs a
# secret_id to authenticate).
set -euo pipefail

: "${VAULT_ADDR:=https://vault.stump.rocks}"
export VAULT_ADDR
ROLE="personal-vault-agent"
POLICY="personal-vault-agent"

command -v vault >/dev/null || { echo "vault CLI not found" >&2; exit 1; }
vault token lookup >/dev/null 2>&1 || {
  echo "Not authenticated to $VAULT_ADDR — run: vault login -method=oidc" >&2; exit 1; }

echo "→ writing policy '$POLICY' (read-only, scoped to secret/personal/*) …"
vault policy write "$POLICY" - <<'HCL'
# Personal Vault Agent — READ-ONLY access to the personal secret tree it renders.
# The agent only reads; new secrets are provisioned by the human admin token.

# List the personal KV tree (the render template ranges over it).
path "secret/metadata/personal" {
  capabilities = ["list"]
}
path "secret/metadata/personal/*" {
  capabilities = ["list", "read"]
}

# Read every personal KV secret (llm, gitea, pocketid, garage, outline, aws, ssh…).
path "secret/data/personal/*" {
  capabilities = ["read"]
}

# Future: dynamic short-lived AWS creds (secrets-aws.env.ctmpl repointed here).
path "aws/creds/personal-cli" {
  capabilities = ["read"]
}
HCL

echo "→ ensuring approle auth is enabled …"
vault auth list -format=json | grep -q '"approle/"' || vault auth enable approle

echo "→ writing role '$ROLE' (periodic token + non-expiring secret_id) …"
vault write "auth/approle/role/$ROLE" \
  token_policies="$POLICY" \
  token_ttl="1h" \
  token_period="1h" \
  token_max_ttl="0" \
  secret_id_ttl="0" \
  secret_id_num_uses="0" \
  token_num_uses="0"

echo
echo "role_id for $ROLE:"
vault read -field=role_id "auth/approle/role/$ROLE/role-id"
echo
echo "✓ done. Provision a host with:  czapprole <host>"
