#!/usr/bin/env bats
# Tests for the `embeddings` block in dot_config/crush/crush.json.tmpl — the
# config that turns on the fork's semantic_index / semantic_search tools
# (joestump-agent/crush#278).
#
# Two things here are load-bearing and neither is obvious from reading the JSON:
#
#   1. The block must render unconditionally, like every provider beside it. An
#      `if env` gate would drop it on any apply from a thin environment (a
#      launchd/systemd timer, an agent's non-interactive Bash) — and unlike a
#      missing provider, which fails loudly at startup, a missing embeddings
#      block just makes both tools quietly absent from the palette. That is the
#      same silent-degradation shape as the providers outage; see the header of
#      test/crush-providers.bats.
#
#   2. dimension must match what the model actually emits. BAAI/bge-m3 returns
#      1024 floats and text-embeddings-inference ignores OpenAI's `dimensions`
#      truncation parameter, so the number is fixed by the model, not chosen.
#      Crush bakes it into the vec0 table on creation; a wrong value means every
#      insert mismatches and the tools disable themselves for the run.
load test_helper

TMPL="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

_render() {
  env -i HOME="$HOME" PATH="$PATH" "$@" \
    bash -c 'chezmoi execute-template --source "$0" < "$1"' "$REPO_ROOT" "$TMPL"
}

@test "embeddings renders with a completely empty environment" {
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
e = json.load(sys.stdin)["embeddings"]
assert e["base_url"] == "https://litellm.stump.rocks/v1", e
assert e["model"] == "bge-m3", e
'
}

@test "embeddings is byte-identical with and without secrets present" {
  empty="$(_render)"
  full="$(_render LITELLM_API_KEY=1 OPENAI_API_KEY=1)"
  [ -n "$empty" ]
  run bash -c 'diff <(printf "%s" "$1" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)[\"embeddings\"],sort_keys=True,indent=2))") \
                    <(printf "%s" "$2" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)[\"embeddings\"],sort_keys=True,indent=2))")' \
      _ "$empty" "$full"
  [ "$status" -eq 0 ]
}

@test "the embeddings api_key is a \$VAR reference, never a literal" {
  run _render LITELLM_API_KEY=supersecret
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
raw = sys.stdin.read()
assert "supersecret" not in raw, "a literal secret leaked into the render"
e = json.loads(raw)["embeddings"]
assert e["api_key"].startswith("$"), e
'
}

@test "dimension matches what bge-m3 actually emits (1024)" {
  # If the model ever changes, this number changes with it — and an existing
  # index has to be dropped, because the vec0 table cannot be resized.
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
e = json.load(sys.stdin)["embeddings"]
assert e["model"] == "bge-m3", "model changed; re-derive dimension: %r" % e
assert e["dimension"] == 1024, e
'
}

@test "embeddings goes through the LiteLLM gateway, not the oauth2-proxied vhost" {
  # https://bge-m3.stump.wtf answers a Bearer token with an SSO redirect. Crush
  # speaks plain OpenAI auth, so the gateway is the only path that works.
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
e = json.load(sys.stdin)["embeddings"]
assert "bge-m3.stump" not in e["base_url"], e
assert e["base_url"].startswith("https://litellm."), e
'
}

@test "both semantic tools are in the permission allowlist" {
  run _render
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json,sys
allowed = set(json.load(sys.stdin)["permissions"]["allowed_tools"])
missing = {"semantic_search", "semantic_index"} - allowed
assert not missing, "not allowlisted: %s" % sorted(missing)
'
}
