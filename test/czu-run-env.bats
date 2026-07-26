#!/usr/bin/env bats
# Regression tests for the secret environment czu-run.zsh applies under.
#
# The bug: the scheduled czu (launchd plist carries only PATH + VAULT_ADDR; the
# systemd unit sets no EnvironmentFile at all) ran `chezmoi apply` with an empty
# secret environment. dot_config/crush/crush.json.tmpl gates each provider on
# `env "SOME_KEY"` at APPLY time, so every 6 hours it rendered `"providers": {}`
# and silently disabled all of Crush's providers until the next interactive apply.
#
# These assert the two halves of the fix: czu-run sources the environment, and
# the template actually recovers when it does.
load test_helper

CZU_RUN="$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
CRUSH_TMPL="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

@test "czu-run: sources the vault secrets before running chezmoi apply" {
  src_line=$(grep -n 'secrets-static\.env' "$CZU_RUN" | head -1 | cut -d: -f1)
  apply_line=$(grep -n '^chezmoi apply' "$CZU_RUN" | head -1 | cut -d: -f1)
  [ -n "$src_line" ]
  [ -n "$apply_line" ]
  [ "$src_line" -lt "$apply_line" ]
}

@test "czu-run: also sources env.zsh, where OPENAI_DIRECT_API_KEY is derived" {
  # Not rendered by Vault Agent — env.zsh computes it from the raw OPENAI_API_KEY
  # before the LiteLLM shadow. Secrets-only sourcing still drops Crush's `openai`.
  secrets_line=$(grep -n 'secrets-static\.env' "$CZU_RUN" | head -1 | cut -d: -f1)
  envzsh_line=$(grep -n 'custom/env\.zsh' "$CZU_RUN" | head -1 | cut -d: -f1)
  [ -n "$envzsh_line" ]
  # oh-my-zsh order: 00-secrets.zsh then env.zsh, since env.zsh derives from it.
  [ "$secrets_line" -lt "$envzsh_line" ]
}

@test "czu-run: the sourcing is guarded so an unprovisioned node still applies" {
  run grep -E '\[\[ -r "\$HOME/\.config/vault/secrets-static\.env" \]\]' "$CZU_RUN"
  [ "$status" -eq 0 ]
}

@test "czu-run: exports what it sources (set -a), or the template gates see nothing" {
  # `. file` alone would define but not export; chezmoi's `env "X"` reads the
  # process environment, so the allexport bracket is load-bearing.
  run grep -c 'set -a' "$CZU_RUN"
  [ "$status" -eq 0 ]
  run grep -c 'set +a' "$CZU_RUN"
  [ "$status" -eq 0 ]
}

@test "czu-run: is valid zsh" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  run zsh -n "$CZU_RUN"
  [ "$status" -eq 0 ]
}

@test "crush.json: an empty secret environment renders NO providers (the bug)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # Pins the failure mode itself, so the gating change is never made silently.
  run bash -c "env -u OPENAI_DIRECT_API_KEY -u LITELLM_API_KEY -u GEMINI_API_KEY \
      -u ZAI_API_TOKEN -u HYPER_API_KEY \
      chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_TMPL' \
    | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"providers\"]; assert p == {}, p'"
  [ "$status" -eq 0 ]
}

@test "crush.json: sourcing the env recovers every provider" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  [ -r "$HOME/.config/vault/secrets-static.env" ] || skip "node not provisioned by Vault Agent"
  # Exactly what czu-run.zsh now does, from a launchd-shaped environment.
  run bash -c "set -a; . \"\$HOME/.config/vault/secrets-static.env\"; \
      [ -r \"\$HOME/.oh-my-zsh/custom/env.zsh\" ] && . \"\$HOME/.oh-my-zsh/custom/env.zsh\"; set +a; \
      chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_TMPL' \
    | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"providers\"]; assert p, \"no providers rendered\"'"
  [ "$status" -eq 0 ]
}
