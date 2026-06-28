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
  ssh -t -L "${port}:localhost:${port}" "$host" \
    "VAULT_ADDR=$addr vault login -method=oidc"
}
