#!/usr/bin/env bash
# openbao-approle-setup.sh — SERVER-SIDE, run ONCE as an OpenBao admin.
#
# Gives the personal Vault Agent a machine identity it can renew FOREVER without a
# human. Replaces the old `token_file` auto-auth (an OIDC-seeded token that died at
# max-TTL — see OMG 2026-07-01 / dotfiles#1). AppRole tokens are periodic (renew
# indefinitely) and the secret_id never expires, so the agent re-authenticates on
# its own for the life of the machine.
#
# Idempotent: re-running just rewrites the role. The ACL policy it binds to is
# managed in Ansible (stumpcloud/ansible → playbooks/services/openbao-policies.yaml),
# NOT here. It does NOT mint a secret_id — that is per-host and handed out by
# `czapprole <host>` / `czinit` from your authenticated laptop session.
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
# The ACL policy this role binds to is managed in Ansible, NOT here:
#   stumpcloud/ansible → playbooks/services/openbao-policies.yaml (user-agent-read)
# It is read-only and templated on identity.entity.name, so the agent reads only
# its own secret/users/<name>/* tree. Defining the policy here too would be a second
# source of truth — exactly the drift that stranded the agent on stale secrets after
# the secret/personal/* → secret/users/$USER/* migration (updated in one place, not
# the other). One source of truth: Ansible.
#
# NOTE: the templated policy only resolves if this AppRole's OpenBao identity entity
# is named after the user (e.g. `joestump`). That entity is set up once by merging
# the operator's OIDC + AppRole aliases into a single named entity; a bare fresh
# AppRole login creates an auto-named entity the template won't match.
POLICY="user-agent-read"

command -v vault >/dev/null || { echo "vault CLI not found" >&2; exit 1; }
vault token lookup >/dev/null 2>&1 || {
  echo "Not authenticated to $VAULT_ADDR — run: vault login -method=oidc" >&2; exit 1; }

echo "→ verifying policy '$POLICY' exists (managed by stumpcloud/ansible openbao-policies.yaml) …"
vault policy read "$POLICY" >/dev/null 2>&1 || {
  echo "Policy '$POLICY' not found on $VAULT_ADDR. Apply it first from stumpcloud/ansible:" >&2
  echo "  VAULT_TOKEN=<admin> pipenv run ansible-playbook -i dub.yaml playbooks/services/openbao-policies.yaml" >&2
  exit 1; }

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
