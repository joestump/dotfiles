#!/usr/bin/env bats
# Tests for the per-user OpenBao layout: the Vault Agent renders each identity's
# secrets from secret/users/$USER/* (not the shared secret/personal/*), scoped by
# the OS login name exported as $USER. The ssh-key + aws file templates are gated
# on .vaultSshAwsUsers so a user without those categories never writes an empty
# file over a real ~/.ssh/id_rsa. See dot_config/vault/*.ctmpl + agent.hcl.tmpl.
load test_helper

V="$REPO_ROOT/dot_config/vault"

# ----- render templates read the per-user path, never the old shared one -----

@test "no render template references the retired secret/personal/ path" {
  run grep -REn 'secret/(data|metadata)/personal/' \
    "$V/secrets-static.env.ctmpl" \
    "$V/secrets-aws.env.ctmpl" \
    "$V/ssh-id_rsa.ctmpl" \
    "$V/ssh-id_rsa-pub.ctmpl"
  # grep exits 1 (no matches) when the path is fully retired.
  [ "$status" -eq 1 ]
}

@test "secrets-static.env.ctmpl ranges over secret/users/\$USER/*" {
  grep -q 'secret/metadata/users/%s/' "$V/secrets-static.env.ctmpl"
  grep -q 'secret/data/users/%s/%s' "$V/secrets-static.env.ctmpl"
  grep -q 'env "USER"' "$V/secrets-static.env.ctmpl"
}

@test "ssh + aws ctmpls read secret/users/\$USER/{ssh,aws}" {
  grep -q 'secret/data/users/%s/ssh' "$V/ssh-id_rsa.ctmpl"
  grep -q 'secret/data/users/%s/ssh' "$V/ssh-id_rsa-pub.ctmpl"
  grep -q 'secret/data/users/%s/aws' "$V/secrets-aws.env.ctmpl"
  grep -q 'env "USER"' "$V/secrets-aws.env.ctmpl"
}

# ----- the Vault Agent service must export USER for env "USER" to resolve -----

@test "systemd + launchd units export USER to the agent" {
  grep -q 'Environment=USER={{ .chezmoi.username }}' \
    "$REPO_ROOT/dot_config/systemd/user/vault-agent.service.tmpl"
  grep -q '<string>{{ .chezmoi.username }}</string>' \
    "$REPO_ROOT/Library/LaunchAgents/rocks.stump.vault-agent.plist.tmpl"
}

# ----- ssh/aws file rendering is gated on .vaultSshAwsUsers -----

@test "agent.hcl.tmpl gates the ssh + aws stanzas on .vaultSshAwsUsers" {
  grep -q 'has .chezmoi.username .vaultSshAwsUsers' "$V/agent.hcl.tmpl"
}

@test ".vaultSshAwsUsers is defined in chezmoi data" {
  grep -q '^vaultSshAwsUsers:' "$REPO_ROOT/.chezmoidata.yaml"
}

# ----- rendered agent.hcl: gate excludes non-listed users, includes listed -----

@test "agent.hcl renders ssh/aws only for a .vaultSshAwsUsers member" {
  command -v chezmoi >/dev/null || skip "chezmoi not installed"
  # A user NOT in the list (any CI runner username) gets no ssh/aws stanza.
  run bash -c 'echo "{{ if has \"nobody-agent\" .vaultSshAwsUsers }}HAS{{ else }}NONE{{ end }}" | chezmoi execute-template --source "'"$REPO_ROOT"'"'
  [ "$status" -eq 0 ]
  [[ "$output" == *NONE* ]]
  # A listed user (joestump) does.
  run bash -c 'echo "{{ if has \"joestump\" .vaultSshAwsUsers }}HAS{{ else }}NONE{{ end }}" | chezmoi execute-template --source "'"$REPO_ROOT"'"'
  [ "$status" -eq 0 ]
  [[ "$output" == *HAS* ]]
}
