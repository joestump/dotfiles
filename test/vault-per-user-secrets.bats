#!/usr/bin/env bats
# Tests for the per-user OpenBao layout: the Vault Agent renders each identity's
# secrets from secret/users/$USER/* (not the shared secret/personal/*), scoped by
# the OS login exported as $USER. SSH keys follow the same auto-discovery pattern
# as env vars — ssh-keys.ctmpl writeToFile()s every field of secret/users/$USER/ssh
# to ~/.ssh/<field>, so no per-key template or gating is needed. See
# dot_config/vault/*.ctmpl + agent.hcl.tmpl.
load test_helper

V="$REPO_ROOT/dot_config/vault"

# ----- render templates read the per-user path, never the old shared one -----

@test "no render template references the retired secret/personal/ path" {
  run grep -REn 'secret/(data|metadata)/personal/' \
    "$V/secrets-static.env.ctmpl" \
    "$V/secrets-aws.env.ctmpl" \
    "$V/ssh-keys.ctmpl"
  [ "$status" -eq 1 ]  # grep exits 1 = no matches = path fully retired
}

@test "secrets-static.env.ctmpl ranges over secret/users/\$USER/*" {
  grep -q 'secret/metadata/users/%s/' "$V/secrets-static.env.ctmpl"
  grep -q 'secret/data/users/%s/%s' "$V/secrets-static.env.ctmpl"
  grep -q 'env "USER"' "$V/secrets-static.env.ctmpl"
}

@test "secrets-aws.env.ctmpl reads secret/users/\$USER/aws" {
  grep -q 'secret/data/users/%s/aws' "$V/secrets-aws.env.ctmpl"
  grep -q 'env "USER"' "$V/secrets-aws.env.ctmpl"
}

# ----- SSH keys: dynamic auto-discovery, like the env bag -----

@test "ssh-keys.ctmpl auto-discovers the whole ssh bag via writeToFile" {
  grep -q 'secret/data/users/%s/ssh' "$V/ssh-keys.ctmpl"
  grep -q 'range \$name, \$content' "$V/ssh-keys.ctmpl"   # ranges every field
  grep -q 'writeToFile' "$V/ssh-keys.ctmpl"
  grep -q 'env "USER"' "$V/ssh-keys.ctmpl"
  grep -q 'env "HOME"' "$V/ssh-keys.ctmpl"
}

@test "ssh-keys.ctmpl hardcodes no specific key name (no id_rsa/id_ed25519)" {
  run grep -Eo 'id_(rsa|ed25519|ecdsa|dsa)' "$V/ssh-keys.ctmpl"
  [ "$status" -eq 1 ]  # none found
}

@test "the hardcoded per-key ssh ctmpls are gone" {
  [ ! -e "$V/ssh-id_rsa.ctmpl" ]
  [ ! -e "$V/ssh-id_rsa-pub.ctmpl" ]
}

@test "*.pub fields get 0644, private keys 0600" {
  grep -q '"0644"' "$V/ssh-keys.ctmpl"
  grep -q '"0600"' "$V/ssh-keys.ctmpl"
}

# ----- no gating left: agent.hcl renders unconditionally -----

@test "agent.hcl.tmpl has no vaultSshAwsUsers gating" {
  run grep -c 'vaultSshAwsUsers' "$V/agent.hcl.tmpl"
  [[ "$output" == "0" ]]
  run grep -c 'vaultSshAwsUsers' "$REPO_ROOT/.chezmoidata.yaml"
  [[ "$output" == "0" ]]
}

@test "agent.hcl.tmpl registers the ssh-keys template" {
  grep -q 'ssh-keys.ctmpl' "$V/agent.hcl.tmpl"
}

# ----- the Vault Agent service must export USER + HOME for the ctmpls -----

@test "systemd + launchd units export USER and HOME to the agent" {
  local svc="$REPO_ROOT/dot_config/systemd/user/vault-agent.service.tmpl"
  local plist="$REPO_ROOT/Library/LaunchAgents/rocks.stump.vault-agent.plist.tmpl"
  grep -q 'Environment=USER={{ .chezmoi.username }}' "$svc"
  grep -q 'Environment=HOME={{ .chezmoi.homeDir }}' "$svc"
  grep -q '<key>USER</key>' "$plist"
  grep -q '<key>HOME</key>' "$plist"
}
