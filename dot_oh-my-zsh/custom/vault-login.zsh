# Run FROM the laptop to tunnel into a remote and log in there in one step.
# (Complementary to `vault-oidc-login`, which is run ON the remote.)
#
# Usage:
#   vault-login <host> [port]              # default role: self-service
#   vault-login -r admin <host> [port]     # explicit role
#
# The role is a FLAG, not a positional: `<host> [port]` is the documented
# signature (Architecture.md, website/docs/secrets.md), so a third positional
# would turn `vault-login ie01 8300` into `role=8300`.
vault-login() {
  emulate -L zsh
  local role
  while [[ $1 == -* ]]; do
    case $1 in
      -r|--role) role=$2; shift 2 ;;
      *) print -u2 "usage: vault-login [-r <role>] <host> [port]"; return 2 ;;
    esac
  done
  local host=$1
  local port=${2:-8250}
  local addr=${VAULT_ADDR:-https://vault.stump.rocks}
  if [[ -z $host ]]; then
    print -u2 "usage: vault-login [-r <role>] <host> [port]"
    return 2
  fi
  # The role is interpolated into the double-quoted remote command below, so an
  # unvalidated value would be executed by the remote shell. OIDC role names are
  # plain identifiers; anything else is a mistake worth refusing.
  # Written as a negated character class rather than `[A-Za-z0-9_-]##`: the
  # `##` repeat operator needs EXTENDED_GLOB, which `emulate -L zsh` turns off,
  # so that form silently rejects every role including valid ones.
  if [[ -n $role && $role == *[^A-Za-z0-9_-]* ]]; then
    print -u2 "vault-login: invalid role '$role' (expected [A-Za-z0-9_-]+)"
    return 2
  fi
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 "vault-login: local port $port already in use"
    return 1
  fi
  # Log in over the tunnel AND kick the remote's Vault Agent so secrets populate
  # in one step (systemd --user on Linux, launchd on macOS — whichever exists).
  ssh -t -L "${port}:localhost:${port}" "$host" \
    "export VAULT_ADDR=$addr; vault login -method=oidc ${role:+role=$role} && { systemctl --user restart vault-agent 2>/dev/null || systemctl --user enable --now vault-agent 2>/dev/null || launchctl kickstart -k gui/\$(id -u)/rocks.stump.vault-agent 2>/dev/null; echo '✅ logged in + Vault Agent kicked — secrets rendering'; }"
}
