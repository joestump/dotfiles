# Provision a host's Vault Agent with an AppRole machine identity so it renews
# ITSELF forever — no human, no OIDC max-TTL death (OMG 2026-07-01 / dotfiles#1).
#
# Run from your authenticated laptop. Mints a fresh secret_id, ships role_id +
# secret_id to ~/.config/vault/approle/ on the target (0600), re-renders the agent
# config (which flips to approle auth once the secret-id file exists), and restarts
# the agent. Server-side role/policy come from scripts/openbao-approle-setup.sh.
#
# Prefers the host's OWN role `vault-agent-<host>` (dotfiles#12: revoke one box
# without re-provisioning the fleet); falls back to the legacy shared
# `personal-vault-agent` so pre-migration hosts keep working.
#
#   czapprole joestump@ie01.stump.rocks     # remote host over SSH
#   czapprole --local                       # this machine (no SSH)
czapprole() {
  emulate -L zsh
  export VAULT_ADDR="${VAULT_ADDR:-https://vault.stump.rocks}"

  local target=$1
  [[ -z $target ]] && { print -u2 "usage: czapprole <host>|--local   e.g. czapprole joestump@ie01.stump.rocks"; return 2 }

  # Need an authenticated provisioner session locally to mint the secret_id.
  if ! vault token lookup >/dev/null 2>&1; then
    print -u2 "czapprole: not authenticated to $VAULT_ADDR — run 'vault-oidc-login' first."; return 1
  fi

  local short role rid sid
  if [[ $target == "--local" ]]; then short=$(hostname -s); else short=${${target#*@}%%.*}; fi
  short=${short:l}
  role="vault-agent-${short}"
  rid=$(vault read -field=role_id "auth/approle/role/${role}/role-id" 2>/dev/null) || {
    role="personal-vault-agent"
    rid=$(vault read -field=role_id "auth/approle/role/${role}/role-id" 2>/dev/null) || {
      print -u2 "czapprole: neither 'vault-agent-${short}' nor '${role}' exists — run scripts/openbao-approle-setup.sh ${short} (admin) first."; return 1; }
    print -u2 "czapprole: ⚠ using the shared legacy role — for per-host revocation run scripts/openbao-approle-setup.sh ${short}, then re-run me"
  }
  print -u2 "→ provisioning with role '${role}'"
  sid=$(vault write -f -field=secret_id "auth/approle/role/${role}/secret-id" 2>/dev/null) || {
    print -u2 "czapprole: could not mint a secret_id (need write on auth/approle/role/${role}/secret-id)."; return 1; }

  if [[ $target == "--local" ]]; then
    local d="$HOME/.config/vault/approle"
    ( umask 077; mkdir -p "$d"; print -rn -- "$rid" > "$d/role-id"; print -rn -- "$sid" > "$d/secret-id" )
    print -u2 "→ approle creds written to $d (0600) — re-rendering agent config + restarting …"
    chezmoi apply "$HOME/.config/vault/agent.hcl" 2>/dev/null
    vault-agent restart
  else
    print -u2 "→ shipping approle creds to ${target} …"
    print -rn -- "$rid" | ssh "$target" 'umask 077; d=~/.config/vault/approle; mkdir -p "$d"; cat > "$d/role-id"' \
      || { print -u2 "czapprole: failed to write role-id on ${target}"; return 1; }
    print -rn -- "$sid" | ssh "$target" 'umask 077; d=~/.config/vault/approle; cat > "$d/secret-id"' \
      || { print -u2 "czapprole: failed to write secret-id on ${target}"; return 1; }
    print -u2 "→ re-rendering agent config + restarting Vault Agent on ${target} …"
    ssh -t "$target" 'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; chezmoi apply ~/.config/vault/agent.hcl 2>/dev/null; systemctl --user restart vault-agent 2>/dev/null || launchctl kickstart -k gui/$(id -u)/rocks.stump.vault-agent 2>/dev/null; echo "✓ vault-agent switched to AppRole auth — self-renewing now"'
  fi
}
