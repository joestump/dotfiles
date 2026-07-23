#!/usr/bin/env bats
# Tests for dot_config/crush/crush.json.tmpl — the providers block renders only
# when each provider's secret is present in the env, and the leading-comma
# separator ($sep) keeps the JSON valid for every subset (including none). A
# regression that drops a `{{- $sep = "," }}` line silently produces invalid
# JSON that Crush rejects at startup, so we render under every env combination
# and parse each result.
load test_helper

TMPL="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

# Render the template with a controlled environment and emit the JSON on stdout.
# Args: a list of VAR=value assignments to export into the render shell.
_render() {
  local vars=("$@")
  local env_prefix=()
  for v in "${vars[@]}"; do env_prefix+=("$v"); done
  env -i HOME="$HOME" PATH="$PATH" "${env_prefix[@]}" \
    bash -c 'chezmoi execute-template --source "$0" < "$1"' "$REPO_ROOT" "$TMPL"
}

@test "providers block is empty when no LLM secrets are present" {
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["providers"]=={}, d["providers"]'
}

@test "Hyper provider renders with the correct openai-compat fields when HYPER_API_KEY is set" {
  run _render HYPER_API_KEY=fake
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "hyper" in d["providers"], d["providers"]'
  # Spot-check the fields that must be present for Crush to treat it as
  # openai-compat and discover models.
  printf '%s' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["providers"]["hyper"]
assert p["type"]=="openai-compat", p
assert p["base_url"]=="https://hyper.charm.land/v1", p
assert p["api_key"]=="$HYPER_API_KEY", p
assert p["discover_models"] is True, p
'
}

@test "Hyper is absent when HYPER_API_KEY is unset but other secrets are present" {
  run _render OPENAI_DIRECT_API_KEY=fake ZAI_API_TOKEN=fake
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "hyper" not in d["providers"], d["providers"]
assert set(d["providers"])=={"openai","zai"}, d["providers"]
'
}

@test "rendered JSON is valid for every combination of LLM secrets" {
  # The leading-comma ($sep) trick is the only thing keeping the JSON valid
  # when an arbitrary subset of providers materializes. Walk the power set.
  local combos=(
    ""
    "OPENAI_DIRECT_API_KEY=1"
    "LITELLM_API_KEY=1"
    "GEMINI_API_KEY=1"
    "ZAI_API_TOKEN=1"
    "HYPER_API_KEY=1"
    "OPENAI_DIRECT_API_KEY=1 LITELLM_API_KEY=1"
    "OPENAI_DIRECT_API_KEY=1 HYPER_API_KEY=1"
    "ZAI_API_TOKEN=1 HYPER_API_KEY=1"
    "GEMINI_API_KEY=1 HYPER_API_KEY=1"
    "OPENAI_DIRECT_API_KEY=1 LITELLM_API_KEY=1 GEMINI_API_KEY=1 ZAI_API_TOKEN=1 HYPER_API_KEY=1"
  )
  for c in "${combos[@]}"; do
    run _render $c
    [ "$status" -eq 0 ] || { echo "COMBO:[$c]"; echo "$output"; false; }
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || {
      echo "INVALID JSON for combo: [$c]"; echo "$output"; false
    }
  done
}
