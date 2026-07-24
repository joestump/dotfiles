#!/usr/bin/env bats
# Tests for the crush-glm harness seed (dot_config/harness/*, dot_local/share/crush-glm/*).
#
# The three files have to agree with each other and with dot_config/crush/crush.json.tmpl
# or the harness silently runs the wrong model, or with no Signal channel. These
# assertions pin the couplings that a careless edit to any one file would break.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/create_harness.toml.tmpl"
HARNESS_ENV="$REPO_ROOT/dot_config/harness/crush-glm.env.tmpl"
MODEL_PIN="$REPO_ROOT/dot_local/share/crush-glm/create_crush.json.tmpl"
CRUSH_JSON="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

_render() {
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

@test "harness: seed files use the create_ attribute so the TUI can own them" {
  # harness's new-harness form and crush both rewrite these files wholesale. A
  # normally-managed file would be clobbered on the next apply.
  [ -f "$HARNESS_TOML" ]
  [ -f "$MODEL_PIN" ]
}

@test "harness: rendered harness.toml is valid TOML with one harness" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
d = tomllib.load(sys.stdin.buffer)
h = d[\"harness\"][\"crush-glm\"]
assert list(d[\"harness\"]) == [\"crush-glm\"], d[\"harness\"]
assert h[\"cmd\"].endswith(\"/.local/bin/crush\"), h[\"cmd\"]
assert h[\"enabled\"] is False, \"a --yolo agent must not autostart\"
'"
  [ "$status" -eq 0 ]
}

@test "harness: crush-glm runs --yolo with the signal MCP opted in as a channel" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  # Channels are CLI-only in crush (no config key), so they must live in args.
  [[ "$output" == *'"--yolo"'* ]]
  [[ "$output" == *'"--channels", "signal"'* ]]
}

@test "harness: cmd is an absolute path (harness does not expandHome it)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  # spawn.go expands ~ for workdir and env_file only — a "~/..." cmd would not exec.
  [[ "$output" != *'cmd = "~'* ]]
  [[ "$output" == *'cmd = "/'* ]]
}

@test "harness: env_file repoints CRUSH_GLOBAL_DATA at the model-pin dir" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_ENV"
  [ "$status" -eq 0 ]
  # Must point at the dir holding create_crush.json.tmpl's target, or the pin is inert.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_ENV' | grep -c '^CRUSH_GLOBAL_DATA=/.*/\.local/share/crush-glm\$'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "harness: env_file carries no secrets (it is committed)" {
  run grep -nE "API_KEY *=|TOKEN *=|SECRET *=|PASSWORD *=" "$HARNESS_ENV"
  [ "$status" -ne 0 ]
}

@test "harness: the model pin is glm-5.2 on the zai provider specifically" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # glm-5.2 is served by BOTH zai and hyper, so the provider must be pinned too.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$MODEL_PIN' | python3 -c '
import json,sys
m = json.load(sys.stdin)[\"models\"]
assert m[\"large\"] == {\"model\": \"glm-5.2\", \"provider\": \"zai\"}, m[\"large\"]
assert m[\"small\"][\"provider\"] == \"zai\", m[\"small\"]
'"
  [ "$status" -eq 0 ]
}

@test "harness: pinned models exist in the zai provider catalog" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Guards against a typo'd id, which crush would silently fail to resolve.
  for id in glm-5.2 glm-4.7-flashx; do
    run bash -c "chezmoi execute-template --source '$REPO_ROOT' '{{ range .crush.zaiModels }}{{ .id }} {{ end }}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$id"* ]]
  done
}

@test "harness: the signal MCP requires the cc prefix on Joe's own number" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # The harness's --channels signal is only useful if the MCP is in channel mode;
  # --prefix cc is what makes signal-mcp DROP unprefixed inbound messages.
  run _render "$CRUSH_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"--channel"'* ]]
  [[ "$output" == *'"--prefix"'* ]]
  [[ "$output" == *'"cc"'* ]]
  [[ "$output" == *'"+12062257886"'* ]]
}

@test "harness: the channel-enabled MCP server is actually named 'signal'" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # crush matches --channels entries against MCP server names; a rename would
  # silently disable the channel.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON' | python3 -c '
import json,sys
mcp = json.load(sys.stdin)[\"mcp\"]
assert \"signal\" in mcp, sorted(mcp)
'"
  [ "$status" -eq 0 ]
}
