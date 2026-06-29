#!/bin/sh
# Git credential helper for gitea.stump.rocks — managed by chezmoi.
#
# Hands git the Gitea token so private clones/pulls authenticate with no token in
# the URL. Source order:
#   1. The Vault-Agent-rendered secrets (secret/personal/gitea → GITEA_TOKEN) —
#      steady state; rotates automatically when you change it in OpenBao.
#   2. The bootstrap-seeded ~/.git-credentials (written by `czinit`) — used on a
#      fresh node BEFORE the first `vault login`, when no secrets exist yet.
#
# Wired host-scoped in ~/.config/git/config so git only calls it for Gitea.
# Read-only: answers `get`, ignores `store`/`erase`.

[ "$1" = "get" ] || exit 0

token=""
env_file="$HOME/.config/vault/secrets-static.env"
if [ -r "$env_file" ]; then
  # Subshell so the OTHER secrets never leak into git's env — only the token.
  token="$( . "$env_file" >/dev/null 2>&1; printf '%s' "${GITEA_TOKEN:-}" )"
fi

# Bootstrap fallback: pull the token out of the seeded ~/.git-credentials.
if [ -z "$token" ] && [ -r "$HOME/.git-credentials" ]; then
  token="$(sed -n 's#^https://[^:]*:\([^@]*\)@gitea\.stump\.rocks.*#\1#p' "$HOME/.git-credentials" | head -1)"
fi

[ -n "$token" ] || exit 0
printf 'username=joestump\npassword=%s\n' "$token"
