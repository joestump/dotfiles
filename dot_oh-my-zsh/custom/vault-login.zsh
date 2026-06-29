vault-login() {
  emulate -L zsh
  local host=$1
  local port=${2:-8250}
  local addr=${VAULT_ADDR:-https://vault.stump.rocks}
  if [[ -z $host ]]; then
    print -u2 "usage: vault-login <host> [port]"
    return 2
  fi
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 "vault-login: local port $port already in use"
    return 1
  fi
  # Log in over the tunnel AND kick the remote's Vault Agent so secrets populate
  # in one step (systemd --user on Linux, launchd on macOS — whichever exists).
  ssh -t -L "${port}:localhost:${port}" "$host" \
    "export VAULT_ADDR=$addr; vault login -method=oidc && { systemctl --user restart vault-agent 2>/dev/null || systemctl --user enable --now vault-agent 2>/dev/null || launchctl kickstart -k gui/\$(id -u)/rocks.stump.vault-agent 2>/dev/null; echo '✅ logged in + Vault Agent kicked — secrets rendering'; }"
}
