#!/usr/bin/env bats
# ~/.config/vault must render 0700, not 0755.
#
# The directory holds the Vault Agent token, the rendered secrets-static.env /
# secrets-aws.env, operator-deploy.env and the AppRole material. `czapprole`
# creates it under `umask 077` (dot_oh-my-zsh/custom/vault-approle.zsh), so on
# every provisioned box the real directory is 0700.
#
# Source it as a plain `dot_config/vault` and chezmoi targets 0755 instead —
# which is not just a looser secrets directory, it BREAKS SYNC. chezmoi sees
# the 0700 dir as "changed since chezmoi last wrote it" and prompts before
# overwriting; the 6-hourly scheduled czu has no TTY, so the prompt fails with
# "could not open a new TTY" and the ENTIRE apply aborts — every run script,
# plugin install and MCP merge after it silently stops landing.
#
# The `private_` prefix is what makes chezmoi's target agree with reality.
load test_helper

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
}

@test "vault config is sourced as private_vault (renders 0700)" {
  [ -d "$REPO_ROOT/dot_config/private_vault" ]
  [ ! -e "$REPO_ROOT/dot_config/vault" ]
}

@test "a clean render puts ~/.config/vault at 0700" {
  local dest="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$dest/.config"
  run chezmoi apply --source "$REPO_ROOT" --destination "$dest" \
    --exclude=scripts,externals,encrypted --no-tty "$dest/.config/vault"
  [ "$status" -eq 0 ]

  # 700 on any POSIX stat: BSD/macOS uses -f %Lp, GNU uses -c %a.
  local mode
  mode="$(stat -f '%Lp' "$dest/.config/vault" 2>/dev/null || stat -c '%a' "$dest/.config/vault")"
  [ "$mode" = "700" ]
}

@test "the rendered vault dir carries no drift against the live target" {
  # The regression this guards: `chezmoi status` reporting `MM .config/vault`,
  # which is the state that wedges a no-TTY apply. Skip where the target does
  # not exist (CI containers, a box Vault Agent never provisioned).
  [ -d "$HOME/.config/vault" ] || skip "no ~/.config/vault on this box"
  run chezmoi diff --source "$REPO_ROOT" "$HOME/.config/vault"
  [ "$status" -eq 0 ]
  ! grep -qE '^(old|new) mode' <<<"$output"
}
