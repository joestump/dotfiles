# Static, non-secret profile/environment variables.
#
# This is the home for vars like VAULT_ADDR that must be set in EVERY interactive
# shell — including on a fresh node before any secrets exist (you need VAULT_ADDR
# to run `vault login` the very first time). It loads early: alphabetically before
# secrets.zsh and the vault-*.zsh helpers, so they can rely on it.
#
# Secrets never go here — those come from OpenBao via the Vault Agent (secrets.zsh).
export VAULT_ADDR="https://vault.stump.rocks"
