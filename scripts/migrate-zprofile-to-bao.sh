#!/usr/bin/env bash
# ONE-TIME migration: copy the secrets currently in your environment (from the
# pre-chezmoi ~/.zprofile) into OpenBao, at the exact paths the chezmoi template
# (private_dot_zprofile.tmpl) reads. This script contains NO secret values —
# only variable names and OpenBao paths, so it is safe to commit.
#
# Run from an interactive shell where the OLD ~/.zprofile is still sourced (so
# the variables below are set in your environment), AFTER authenticating to bao:
#
#     bao login -method=oidc          # or: vault-login <host>
#     ~/.local/share/chezmoi/scripts/migrate-zprofile-to-bao.sh
#     chezmoi apply                   # renders ~/.zprofile from OpenBao
#
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR and run from a shell with the old ~/.zprofile sourced}"
command -v bao >/dev/null || { echo "bao (OpenBao CLI) not found on PATH"; exit 1; }

req() {
  local missing=0
  for v in "$@"; do
    [ -n "${!v:-}" ] || { echo "Missing \$$v — is the old ~/.zprofile sourced in this shell?"; missing=1; }
  done
  [ "$missing" -eq 0 ] || exit 1
}

req AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
    OPENAI_API_KEY LITELLM_API_KEY GEMINI_API_KEY \
    GITEA_TOKEN POCKETID_API_KEY \
    GARAGE_ACCESS_KEY GARAGE_SECRET_KEY

echo "Writing secrets to OpenBao under secret/personal/* ..."

bao kv put secret/personal/aws \
  AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

bao kv put secret/personal/llm \
  OPENAI_API_KEY="$OPENAI_API_KEY" \
  LITELLM_API_KEY="$LITELLM_API_KEY" \
  GEMINI_API_KEY="$GEMINI_API_KEY"

bao kv put secret/personal/gitea     GITEA_TOKEN="$GITEA_TOKEN"
bao kv put secret/personal/pocketid  POCKETID_API_KEY="$POCKETID_API_KEY"

bao kv put secret/personal/garage \
  GARAGE_ACCESS_KEY="$GARAGE_ACCESS_KEY" \
  GARAGE_SECRET_KEY="$GARAGE_SECRET_KEY"

echo
echo "✅ Loaded into OpenBao. Next:"
echo "   chezmoi diff         # preview the rendered ~/.zprofile"
echo "   chezmoi apply        # write ~/.zprofile (mode 0600) from OpenBao"
echo "   exec zsh             # reload"
