#!/usr/bin/env bash
# Shared helpers for the secrets setup scripts. Source this:  . "$(dirname "$0")/lib.sh"

vault_addr_default() { export VAULT_ADDR="${VAULT_ADDR:-https://vault.stump.rocks}"; }

is_ssh() { [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; }

# Print the SSH tunnel guidance needed to complete an OIDC login on a remote box.
print_tunnel_hint() {
  local port="${1:-8250}" host user
  host="$(hostname)"; user="${USER:-$(whoami)}"
  cat >&2 <<EOF

🔌 You're on a REMOTE host over SSH. OpenBao OIDC login opens a localhost:${port}
   callback that your laptop browser must reach. Set up a tunnel first:

   Easiest — run on your LAPTOP (opens the tunnel AND logs you in on this host):
       vault-login ${host}

   Manual — on your LAPTOP, in another terminal:
       ssh -L ${port}:localhost:${port} ${user}@${host}
   leave it open, then back HERE run:
       vault login -method=oidc

   If this host also can't reach https://vault.stump.rocks directly, forward that
   too from your laptop and point VAULT_ADDR at the tunnel:
       ssh -L 8200:vault.stump.rocks:443 ${user}@${host}
       export VAULT_ADDR=https://localhost:8200   # add -tls-skip-verify if needed

   (adjust ${host} to however you actually SSH to this box)
EOF
}

# Ensure we have vault + a valid token; give SSH-aware guidance if not.
ensure_vault_auth() {
  vault_addr_default
  command -v vault >/dev/null 2>&1 || { echo "vault CLI not found (brew install hashicorp/tap/vault)" >&2; exit 1; }
  if ! vault token lookup >/dev/null 2>&1; then
    echo "Not authenticated to OpenBao (VAULT_ADDR=$VAULT_ADDR)." >&2
    if is_ssh; then print_tunnel_hint 8250; else echo "Run: vault login -method=oidc" >&2; fi
    exit 1
  fi
}
