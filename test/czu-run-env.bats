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

# The tests below previously pinned the OPPOSITE behaviour: an empty environment
# was expected to render `"providers": {}`, documenting the bug so the gating
# could not be changed silently. It has now been changed deliberately — the gates
# are gone (see the comment at the top of crush.json.tmpl). Sourcing the secrets
# in czu-run.zsh fixed the scheduled-apply path but could never fix a BARE
# `chezmoi apply`, which ~/.claude/hooks/chezmoi-edit-guard.sh tells every agent
# editing this repo to run — so the outage kept coming back on a different path.
# These now pin the fix: the render must not depend on the apply-time environment
# at all.

@test "crush.json: an empty secret environment still renders every provider" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # The regression this guards: any provider gated on `env "..."` silently
  # vanishes here, and Crush refuses to start with "default providers are
  # disabled and there are no custom providers are configured".
  run bash -c "env -u OPENAI_DIRECT_API_KEY -u LITELLM_API_KEY -u GEMINI_API_KEY \
      -u ZAI_API_TOKEN -u ZAI_BASE_URL -u HYPER_API_KEY \
      chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_TMPL' \
    | python3 -c 'import json,sys
p = json.load(sys.stdin)[\"providers\"]
want = {\"openai\", \"litellm\", \"gemini\", \"zai\", \"hyper\"}
assert set(p) == want, \"got %s, want %s\" % (sorted(p), sorted(want))'"
  [ "$status" -eq 0 ]
}

@test "crush.json: credentials are \$VAR references, never literal values" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # Unconditional rendering is only safe because Crush expands these at RUN time.
  # If a real key ever leaked into the render it would land in a world-readable
  # file outside OpenBao — the exact thing the old gating was reaching for.
  run bash -c "set -a; [ -r \"\$HOME/.config/vault/secrets-static.env\" ] && . \"\$HOME/.config/vault/secrets-static.env\"; set +a; \
      chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_TMPL' \
    | python3 -c 'import json,sys
for name, prov in json.load(sys.stdin)[\"providers\"].items():
    key = prov.get(\"api_key\", \"\")
    assert key.startswith(\"\$\"), \"%s: api_key is not a \\\$VAR reference: %r\" % (name, key)'"
  [ "$status" -eq 0 ]
}

@test "crush.json: no apply-time env gates remain around the providers" {
  # The mechanism itself, not just its output: `{{ if env "..." }}` is what made
  # the file environment-dependent. `env "X" | default "y"` is fine (it always
  # produces a value); a bare conditional is not.
  run grep -nE '\{\{-? *if +env +"' "$CRUSH_TMPL"
  [ "$status" -ne 0 ]
}
