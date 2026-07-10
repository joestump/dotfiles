# Authenticate to OpenBao via OIDC, SSH-aware.
#   - On your laptop: runs `vault login` (browser opens locally).
#   - Over SSH: the localhost:8250 OIDC callback can't reach your laptop browser,
#     so this prints the tunnel command and waits for you to open it.
# (Complementary to `vault-login <host>`, which is run FROM the laptop to tunnel
#  into a remote and log in there in one step.)
vault-oidc-login() {
  emulate -L zsh
  local port=8250
  export VAULT_ADDR="${VAULT_ADDR:-https://vault.stump.rocks}"
  if [[ -n $SSH_CONNECTION || -n $SSH_TTY ]]; then
    local host=${HOST:-$(hostname)}
    print -u2 "🔌 SSH session detected — OIDC needs a tunnel for the localhost:${port} callback.\n"
    print -u2 "Easiest — on your LAPTOP (opens tunnel AND logs in here, one step):"
    print -u2 "    vault-login ${host}\n"
    print -u2 "Or manually — on your LAPTOP, in another terminal:"
    print -u2 "    ssh -L ${port}:localhost:${port} ${USER}@${host}"
    print -u2 "leave it open, then continue here.\n"
    print -n "Press Enter once the tunnel is up (Ctrl-C to abort)... "; read -r
  fi
  # ADR-0038 / SPEC-0022: the personal Vault Agent is quarantined to
  # ~/.config/vault/agent-token and no longer sinks to ~/.vault-token, so an OIDC
  # login here STICKS with no agent juggling — ~/.vault-token is the human's alone.
  # On token_file hosts (no AppRole secret-id) the agent AUTHENTICATES from
  # ~/.vault-token, so restart it there to adopt the fresh token.
  if vault login -method=oidc; then
    export VAULT_TOKEN="$(cat "$HOME/.vault-token" 2>/dev/null)"   # use it in this shell too
    if [[ -f "$HOME/.config/vault/approle/secret-id" ]]; then
      print -u2 "✅ OIDC admin session active — token in ~/.vault-token and \$VAULT_TOKEN."
      print -u2 "   (Personal secrets keep rendering via the AppRole agent, untouched.)"
    else
      print -u2 "✅ logged in — restarting the Vault Agent (token_file mode) to adopt the token…"
      vault-agent restart 2>/dev/null || vault-agent start
    fi
  else
    return 1
  fi
}
