# Authenticate to OpenBao via OIDC, SSH-aware.
#   - On your laptop: runs `vault login` (browser opens locally).
#   - Over SSH: the localhost:8250 OIDC callback can't reach your laptop browser,
#     so this prints the tunnel command and waits for you to open it.
# (Complementary to `vault-login <host>`, which is run FROM the laptop to tunnel
#  into a remote and log in there in one step.)
#
# Usage:
#   vault-oidc-login          # default role: self-service (your own
#                             # secret/users/<username>/* tree)
#   vault-oidc-login admin    # explicit role — admin/maintainer are gated on
#                             # Pocket ID group membership via bound_claims
vault-oidc-login() {
  emulate -L zsh
  local role="$1"
  local port=8250
  export VAULT_ADDR="${VAULT_ADDR:-https://vault.stump.rocks}"
  if [[ -n $SSH_CONNECTION || -n $SSH_TTY ]]; then
    local host=${HOST:-$(hostname)}
    print -u2 "🔌 SSH session detected — OIDC needs a tunnel for the localhost:${port} callback.\n"
    print -u2 "Easiest — on your LAPTOP (opens tunnel AND logs in here, one step):"
    # Carry the role through. Without it, following this instruction logs you in
    # on the mount's default_role (self-service) while you asked for admin — and
    # a valid-but-wrong token is worse than a failure, because the later
    # permission denials read as missing objects rather than missing privilege.
    print -u2 "    vault-login ${role:+-r ${role} }${host}\n"
    print -u2 "Or manually — on your LAPTOP, in another terminal:"
    print -u2 "    ssh -L ${port}:localhost:${port} ${USER}@${host}"
    print -u2 "leave it open, then continue here.\n"
    print -n "Press Enter once the tunnel is up (Ctrl-C to abort)... "; read -r
  fi
  if vault login -method=oidc ${role:+role=$role}; then
    # All-in-one: kick the agent so secrets populate immediately (and it re-reads
    # the fresh token). restart if it's already up, else start it.
    print -u2 "✅ logged in — (re)starting the Vault Agent to render secrets…"
    vault-agent restart 2>/dev/null || vault-agent start
  fi
}
