#!/usr/bin/env bash
# openbao-approle-setup.sh — SERVER-SIDE, run as an OpenBao admin.
#
# Gives the personal Vault Agent a machine identity it can renew FOREVER without a
# human. Replaces the old `token_file` auto-auth (an OIDC-seeded token that died at
# max-TTL — see OMG 2026-07-01 / dotfiles#1). AppRole tokens are periodic (renew
# indefinitely) and the secret_id never expires, so the agent re-authenticates on
# its own for the life of the machine.
#
# Two modes (dotfiles#12 — blast radius):
#
#   openbao-approle-setup.sh                     # LEGACY shared role
#       Writes the single shared role `personal-vault-agent`. Kept for
#       back-compat with already-provisioned hosts; new hosts should get
#       per-host roles instead.
#
#   openbao-approle-setup.sh [--cidr CIDRS] [--entity NAME] HOST
#       Writes a PER-HOST role `vault-agent-<HOST>` so one box can be revoked
#       (`vault delete auth/approle/role/vault-agent-<HOST>`) without
#       re-provisioning the fleet. --cidr binds both secret-ids and tokens to
#       the given CIDR list (comma-separated) so leaked creds are useless
#       off-network. The role's login alias is merged into the operator's
#       OpenBao identity entity (--entity, default $USER) — REQUIRED for the
#       templated policy to resolve; without the merge a fresh role logs in as
#       an auto-named entity that reads NOTHING (the dotfiles#1 failure mode).
#
# Idempotent: re-running just rewrites the role and re-verifies the alias. The ACL
# policy it binds to is managed in Ansible (stumpcloud/ansible →
# playbooks/services/openbao-policies.yaml), NOT here. It does NOT mint a
# secret_id — that is per-host and handed out by `czapprole <host>` / `czinit`
# from your authenticated laptop session.
#
#   export VAULT_ADDR=https://vault.stump.rocks
#   vault login -method=oidc          # admin
#   ~/.local/share/chezmoi/scripts/openbao-approle-setup.sh ie01
#
# Prints the role_id at the end (role_id is NOT a secret on its own — it needs a
# secret_id to authenticate).
set -euo pipefail

: "${VAULT_ADDR:=https://vault.stump.rocks}"
export VAULT_ADDR

# The ACL policy this role binds to is managed in Ansible, NOT here:
#   stumpcloud/ansible → playbooks/services/openbao-policies.yaml (user-agent-read)
# It is read-only and templated on identity.entity.name, so the agent reads only
# its own secret/users/<name>/* tree. Defining the policy here too would be a second
# source of truth — exactly the drift that stranded the agent on stale secrets after
# the secret/personal/* → secret/users/$USER/* migration (updated in one place, not
# the other). One source of truth: Ansible.
POLICY="user-agent-read"

CIDRS=""
ENTITY="${USER}"
HOST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cidr)   CIDRS="${2:?--cidr needs a value}"; shift 2 ;;
    --entity) ENTITY="${2:?--entity needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)       echo "unknown flag: $1" >&2; exit 2 ;;
    *)        [ -z "$HOST" ] || { echo "one host per run (got '$HOST' and '$1')" >&2; exit 2; }
              HOST="$1"; shift ;;
  esac
done

if [ -n "$HOST" ]; then
  # Short, lowercase hostname → role name. `ie01.stump.rocks` and `ie01` are the
  # same role; user@host is not accepted here (that's czapprole's argument shape).
  case "$HOST" in *@*) echo "pass a bare hostname, not user@host: $HOST" >&2; exit 2;; esac
  SHORT=$(printf '%s' "$HOST" | cut -d. -f1 | tr '[:upper:]' '[:lower:]')
  ROLE="vault-agent-${SHORT}"
else
  [ -z "$CIDRS" ] || { echo "--cidr requires a HOST (per-host roles only)" >&2; exit 2; }
  ROLE="personal-vault-agent"
fi

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
# Build the write as an array so the CIDR fields only appear when requested.
ARGS=(
  token_policies="$POLICY"
  token_ttl="1h"
  token_period="1h"
  token_max_ttl="0"
  secret_id_ttl="0"
  secret_id_num_uses="0"
  token_num_uses="0"
)
if [ -n "$CIDRS" ]; then
  echo "→ binding secret-ids AND tokens to: $CIDRS"
  ARGS+=(secret_id_bound_cidrs="$CIDRS" token_bound_cidrs="$CIDRS")
fi
vault write "auth/approle/role/$ROLE" "${ARGS[@]}"

ROLE_ID=$(vault read -field=role_id "auth/approle/role/$ROLE/role-id")

if [ -n "$HOST" ]; then
  # Merge this role's login alias into the operator's named identity entity so the
  # entity-templated policy resolves. AppRole aliases are named by role_id.
  command -v jq >/dev/null || { echo "jq required for the identity-alias merge" >&2; exit 1; }

  echo "→ merging role alias into identity entity '$ENTITY' …"
  ACCESSOR=$(vault auth list -format=json | jq -r '."approle/".accessor')
  ENTITY_ID=$(vault read -format=json "identity/entity/name/$ENTITY" 2>/dev/null \
                | jq -r '.data.id') || true
  if [ -z "${ENTITY_ID:-}" ] || [ "$ENTITY_ID" = "null" ]; then
    echo "Identity entity '$ENTITY' not found. It is created once when the operator's" >&2
    echo "OIDC + AppRole aliases are merged into a single named entity. Refusing to" >&2
    echo "continue — a bare login would mint an auto-named entity and the templated" >&2
    echo "policy would read NOTHING (the dotfiles#1 failure mode)." >&2
    exit 1
  fi

  # Idempotency: if an alias for this role_id already exists on the approle mount,
  # verify it points at the right entity rather than erroring on re-create.
  EXISTING=$(vault write -format=json identity/lookup/entity \
               alias_name="$ROLE_ID" alias_mount_accessor="$ACCESSOR" 2>/dev/null \
               | jq -r '.data.id // empty') || true
  if [ -z "$EXISTING" ]; then
    vault write identity/entity-alias \
      name="$ROLE_ID" canonical_id="$ENTITY_ID" mount_accessor="$ACCESSOR" >/dev/null
    echo "  alias created → entity '$ENTITY' ($ENTITY_ID)"
  elif [ "$EXISTING" = "$ENTITY_ID" ]; then
    echo "  alias already merged into '$ENTITY' ✓"
  else
    echo "Alias for role_id $ROLE_ID already belongs to entity $EXISTING (wanted" >&2
    echo "$ENTITY_ID). This host logged in before the merge and minted an auto-named" >&2
    echo "entity. Fix by deleting that entity (or its alias) in OpenBao, then re-run." >&2
    exit 1
  fi
fi

echo
echo "role_id for $ROLE:"
echo "$ROLE_ID"
echo
if [ -n "$HOST" ]; then
  echo "✓ done. Provision the host with:  czapprole ${USER}@${HOST}   (or --local on it)"
  echo "  Revoke just this host later:   vault delete auth/approle/role/$ROLE"
else
  echo "✓ done (legacy shared role). Prefer per-host roles: $0 <host>"
fi
