#!/usr/bin/env bash
# SERVER-SIDE setup (run once, by an OpenBao admin): configure OpenBao to issue
# DYNAMIC, short-lived AWS credentials at  aws/creds/personal-cli.
#
# Why: replaces the static, long-lived AWS_ACCESS_KEY_ID/SECRET that previously
# lived in ~/.zprofile. After this, the Vault Agent fetches fresh creds on a
# lease and rotates them automatically.
#
# PREREQUISITES (you provide these — the script does not invent them):
#   1. `vault login` as an admin with rights to enable secrets engines.
#   2. A bootstrap AWS IAM credential for OpenBao to act as (an IAM user whose
#      policy allows it to mint the dynamic creds). Export it before running:
#         export AWS_VAULT_ROOT_ACCESS_KEY=AKIA...        # the IAM user for OpenBao
#         export AWS_VAULT_ROOT_SECRET_KEY=...
#         export AWS_REGION=us-west-2                      # optional, default below
#
# DECISIONS (edit before running):
#   - credential_type: `iam_user` (creates a throwaway IAM user per request;
#     needs iam:CreateUser/PutUserPolicy/DeleteUser... on the root cred) OR
#     `assumed_role` (no IAM-user churn; needs a role ARN the root cred can
#     assume — generally the better choice). This script defaults to iam_user
#     with a PLACEHOLDER policy you MUST tailor.
set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
ensure_vault_auth   # SSH-aware: prints tunnel guidance if you're remote + unauthed
: "${AWS_VAULT_ROOT_ACCESS_KEY:?set AWS_VAULT_ROOT_ACCESS_KEY (the IAM key OpenBao uses)}"
: "${AWS_VAULT_ROOT_SECRET_KEY:?set AWS_VAULT_ROOT_SECRET_KEY}"
REGION="${AWS_REGION:-us-west-2}"
ROLE="${VAULT_AWS_ROLE:-personal-cli}"

echo "==> enabling aws secrets engine (idempotent)"
vault secrets enable -path=aws aws 2>/dev/null || echo "    (already enabled)"

echo "==> configuring root credential + region"
vault write aws/config/root \
  access_key="$AWS_VAULT_ROOT_ACCESS_KEY" \
  secret_key="$AWS_VAULT_ROOT_SECRET_KEY" \
  region="$REGION"

echo "==> lease TTLs for issued creds (1h default, 24h max)"
vault write aws/config/lease lease=1h lease_max=24h 2>/dev/null || true

echo "==> role aws/roles/$ROLE  (TAILOR THIS POLICY to your needs)"
vault write "aws/roles/$ROLE" \
  credential_type=iam_user \
  policy_document=-<<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:*", "sts:GetCallerIdentity"], "Resource": "*" }
  ]
}
POLICY

echo
echo "✅ Done. Test issuing a credential:"
echo "     vault read aws/creds/$ROLE"
echo "   The Vault Agent template (secrets-aws.env.ctmpl) reads aws/creds/$ROLE."
