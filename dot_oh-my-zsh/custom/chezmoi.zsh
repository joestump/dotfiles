# Dotfiles convenience helpers.

# czu — bring this machine fully current in one step:
#   1. chezmoi update        → git pull + apply the latest config
#   2. vault-agent restart   → re-render secrets from OpenBao now (don't wait ~5m)
#   3. exec zsh              → reload the shell so new config + secrets take effect
# Extra args pass through to chezmoi update (e.g. `czu --refresh-externals`).
czu() {
  emulate -L zsh
  chezmoi update "$@" || return        # stop on failure so the error is visible
  vault-agent restart 2>/dev/null      # best-effort; ok if the agent isn't set up
  [[ -o interactive ]] && exec zsh
}

# czinit <host> — bootstrap the dotfiles on a fresh node over SSH, in one step.
# The private dotfiles repo can't clone on a bare node (no creds yet), so this:
#   1. seeds the node's git credential store with your Gitea token (piped over
#      stdin — never in argv), so the clone authenticates;
#   2. installs chezmoi from get.chezmoi.io and runs `chezmoi init --apply`.
# After it finishes, run `vault-oidc-login` ON the node once to render secrets
# (then the Vault-Agent-backed credential helper takes over and `czu` is hands-off).
#   e.g.  czinit joestump@ie02.stump.rocks
czinit() {
  emulate -L zsh
  local host=$1
  [[ -z $host ]] && { print -u2 "usage: czinit <host>   e.g. czinit joestump@ie02.stump.rocks"; return 2 }
  local repo="https://gitea.stump.rocks/joestump/dotfiles.git"

  # Resolve a Gitea token locally to seed the node (env, then rendered secrets).
  local tok="${GITEA_TOKEN:-}"
  [[ -z $tok && -r ~/.config/vault/secrets-static.env ]] && \
    tok="$( . ~/.config/vault/secrets-static.env >/dev/null 2>&1; printf '%s' "${GITEA_TOKEN:-}" )"
  [[ -z $tok ]] && { print -u2 "czinit: no GITEA_TOKEN locally — run 'vault-oidc-login' first."; return 1 }

  print -u2 "→ seeding Gitea credentials on ${host} …"
  ssh "$host" 'umask 077; cat > ~/.git-credentials && git config --global credential.helper store' \
    <<< "https://joestump:${tok}@gitea.stump.rocks" \
    || { print -u2 "czinit: could not seed credentials on ${host}"; return 1 }

  print -u2 "→ installing chezmoi + applying dotfiles on ${host} (sudo may prompt) …"
  ssh -t "$host" "sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- init --apply '${repo}'"

  print -u2 "\n✓ ${host} bootstrapped. Final step — ON ${host}, run: vault-oidc-login"
}
