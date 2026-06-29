# Load secrets that the Vault Agent renders from OpenBao.
#
# The agent (launchd job rocks.stump.vault-agent) writes ~/.config/vault/secrets-*.env
# on a schedule and keeps them fresh (incl. short-lived dynamic AWS creds). This
# file just sources them — NO network calls at shell startup.
#
# Guarded with nullglob (N): if the agent hasn't rendered anything yet, sourcing is
# a silent no-op and never breaks shell startup. But in an INTERACTIVE shell with
# nothing rendered (fresh node, no `vault login` yet), print a one-line nudge so you
# aren't left guessing why OPENAI_API_KEY / GITEA_TOKEN / etc. are missing.
() {
  local -a rendered=( "${HOME}"/.config/vault/secrets-*.env(N) )
  local f
  for f in "${rendered[@]}"; do
    [[ -r "$f" ]] && source "$f"
  done

  if (( ! ${#rendered} )) && [[ -o interactive ]]; then
    if [[ -n $SSH_CONNECTION || -n $SSH_TTY ]]; then
      print -u2 "🔒 OpenBao: no secrets rendered yet — run 'vault-oidc-login' (over SSH; it prints the tunnel command)."
    else
      print -u2 "🔒 OpenBao: no secrets rendered yet — run 'vault-oidc-login'."
    fi
  fi
}
