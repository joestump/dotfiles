# Dotfiles convenience helpers.

# cu — bring this machine fully current in one step:
#   1. chezmoi update        → git pull + apply the latest config
#   2. vault-agent restart   → re-render secrets from OpenBao now (don't wait ~5m)
#   3. exec zsh              → reload the shell so new config + secrets take effect
# Extra args pass through to chezmoi update (e.g. `cu --refresh-externals`).
cu() {
  emulate -L zsh
  chezmoi update "$@" || return        # stop on failure so the error is visible
  vault-agent restart 2>/dev/null      # best-effort; ok if the agent isn't set up
  [[ -o interactive ]] && exec zsh
}
