# Load secrets that the Vault Agent renders from OpenBao.
#
# The agent (launchd job rocks.stump.vault-agent) writes ~/.config/vault/secrets-*.env
# on a schedule and keeps them fresh (incl. short-lived dynamic AWS creds). This
# file just sources them — NO network calls at shell startup.
#
# Guarded with nullglob (N): if the agent hasn't rendered anything yet, this is a
# silent no-op and never breaks shell startup.
() {
  local f
  for f in "${HOME}"/.config/vault/secrets-*.env(N); do
    [[ -r "$f" ]] && source "$f"
  done
}
