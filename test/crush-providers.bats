#!/usr/bin/env bats
# Tests for dot_config/crush/crush.json.tmpl — the providers block.
#
# This file used to assert the OPPOSITE: each provider rendered only when its
# secret was in the environment at APPLY time, with a leading-comma separator
# ($sep) keeping the JSON valid for every subset. That design caused a recurring
# outage. The secret is only needed when Crush RUNS, so the gate protected
# nothing (the file holds "$VAR" references either way) while making the render
# depend on the environment of whoever happened to run `chezmoi apply`. Any apply
# without the Vault-rendered env — an agent's non-interactive Bash, a launchd or
# systemd timer, a plain subshell — wrote `"providers": {}`: valid JSON, exit 0,
# no warning, and Crush then refused to start with "default providers are
# disabled and there are no custom providers are configured".
#
# The invariant is now the inverse, and it is the thing worth pinning: the
# rendered providers block is IDENTICAL no matter what is in the environment.
load test_helper

TMPL="$REPO_ROOT/dot_config/crush/crush.json.tmpl"
PROVIDERS=(openai litellm gemini zai hyper)

# Render the template with a controlled environment and emit the JSON on stdout.
# Args: a list of VAR=value assignments to export into the render shell.
_render() {
  local vars=("$@")
  local env_prefix=()
  for v in "${vars[@]}"; do env_prefix+=("$v"); done
  env -i HOME="$HOME" PATH="$PATH" "${env_prefix[@]}" \
    bash -c 'chezmoi execute-template --source "$0" < "$1"' "$REPO_ROOT" "$TMPL"
}

@test "every provider renders even with a completely empty environment" {
  # The exact failure mode: this is what a bare `chezmoi apply` from an agent
  # shell or a launchd timer sees.
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
p = json.load(sys.stdin)["providers"]
want = {"openai","litellm","gemini","zai","hyper"}
assert set(p) == want, "got %s, want %s" % (sorted(p), sorted(want))
'
}

@test "the providers block is byte-identical with and without secrets present" {
  # The core invariant. If this ever diverges, some apply-time conditional has
  # crept back in and the outage is one scheduled run away.
  empty="$(_render)"
  full="$(_render OPENAI_DIRECT_API_KEY=1 LITELLM_API_KEY=1 GEMINI_API_KEY=1 \
                  ZAI_API_TOKEN=1 ZAI_BASE_URL=1 HYPER_API_KEY=1)"
  [ -n "$empty" ]
  run bash -c 'diff <(printf "%s" "$1" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)[\"providers\"],sort_keys=True,indent=2))") \
                    <(printf "%s" "$2" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)[\"providers\"],sort_keys=True,indent=2))")' \
      _ "$empty" "$full"
  [ "$status" -eq 0 ]
}

@test "credentials render as \$VAR references, never literal values" {
  # Unconditional rendering is only safe because Crush expands these at run time.
  # A literal key here would sit in a world-readable file outside OpenBao.
  run _render OPENAI_DIRECT_API_KEY=supersecret HYPER_API_KEY=alsosecret
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
raw = sys.stdin.read()
assert "supersecret" not in raw, "a literal secret leaked into the render"
assert "alsosecret" not in raw, "a literal secret leaked into the render"
'
  run _render OPENAI_DIRECT_API_KEY=supersecret HYPER_API_KEY=alsosecret
  printf '%s' "$output" | python3 -c '
import json,sys
for name, prov in json.load(sys.stdin)["providers"].items():
    key = prov.get("api_key","")
    assert key.startswith("$"), "%s: api_key is not a $VAR reference: %r" % (name, key)
'
}

@test "Hyper renders with the correct openai-compat fields" {
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
p = json.load(sys.stdin)["providers"]["hyper"]
assert p["type"] == "openai-compat", p
assert p["base_url"] == "https://hyper.charm.land/v1", p
assert p["api_key"] == "$HYPER_API_KEY", p
assert p["discover_models"] is True, p
'
}

@test "the zai model catalogue survives an empty environment" {
  # zai is the one provider whose block carries data (.crush.zaiModels) rather
  # than just a credential — losing it silently would strip every GLM model.
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
z = json.load(sys.stdin)["providers"]["zai"]
assert z["models"], "zai rendered with no models"
for m in z["models"]:
    assert m["id"] and m["name"], m
'
}

@test "rendered JSON is valid for every combination of LLM secrets" {
  # Kept from the original suite. The subset logic is gone, but the render must
  # still parse under any environment — including partial and nonsense ones.
  local combos=(
    ""
    "OPENAI_DIRECT_API_KEY=1"
    "LITELLM_API_KEY=1"
    "GEMINI_API_KEY=1"
    "ZAI_API_TOKEN=1"
    "HYPER_API_KEY=1"
    "OPENAI_DIRECT_API_KEY=1 LITELLM_API_KEY=1"
    "ZAI_API_TOKEN=1 HYPER_API_KEY=1"
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

@test "no apply-time env gate has crept back into the template" {
  # The mechanism, not just its output. `env "X" | default "y"` is fine — it
  # always yields a value. A bare `if env` conditional is what broke Crush.
  run grep -nE '\{\{-? *if +env +"' "$TMPL"
  [ "$status" -ne 0 ]
}
