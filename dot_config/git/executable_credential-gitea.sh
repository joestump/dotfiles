#!/bin/sh
# Git credential helper for gitea.stump.rocks — managed by chezmoi.
#
# Hands git the Gitea personal access token that the Vault Agent renders from
# OpenBao (secret/personal/gitea → GITEA_TOKEN) into the secrets env file. This
# lets private Gitea clones/pulls authenticate with NO token in the URL and NO
# plaintext ~/.git-credentials — the token only ever lives in the agent-rendered
# secrets file, and rotates automatically when you change it in OpenBao.
#
# Wired host-scoped in ~/.config/git/config so git only calls it for Gitea.
# Read-only: answers `get`, ignores `store`/`erase`.

[ "$1" = "get" ] || exit 0

env_file="$HOME/.config/vault/secrets-static.env"
[ -r "$env_file" ] || exit 0

# Source in a command-substitution subshell so the other secrets never leak into
# git's process environment — only the token is emitted on stdout.
token="$( . "$env_file" >/dev/null 2>&1; printf '%s' "${GITEA_TOKEN:-}" )"
[ -n "$token" ] || exit 0

printf 'username=joestump\npassword=%s\n' "$token"
