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

# czinit <host> — bootstrap a fresh node end-to-end over SSH, in one command:
#   1. seed the node's git credential store with your Gitea token (piped over
#      stdin — never in argv), so the private dotfiles repo can clone;
#   2. install chezmoi from get.chezmoi.io and run `chezmoi init --apply`;
#   3. log in to OpenBao via OIDC (vault-login: tunnel + login + agent kick) so
#      secrets render. You just click Authorize in the browser when it opens.
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
  ssh -t "$host" "sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- init --apply '${repo}'" \
    || { print -u2 "czinit: bootstrap failed on ${host}"; return 1; }

  # Log in to OpenBao right here. OIDC needs one browser click to authorize, but
  # vault-login handles the rest: opens the localhost:8250 tunnel, runs the login
  # on the node, and kicks the Vault Agent so secrets render.
  if (( $+functions[vault-login] )); then
    print -u2 "→ authenticating to OpenBao (OIDC) — click Authorize in the browser tab when it opens …"
    vault-login "$host" \
      || print -u2 "czinit: OIDC step skipped/failed — run 'vault-login ${host}' later to render secrets."
  else
    print -u2 "→ final step — run: vault-login ${host}"
  fi

  print -u2 "\n✓ ${host} bootstrapped — dotfiles applied and (once authorized) secrets rendered."
}
