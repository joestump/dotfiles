#!/usr/bin/env bats
# Tests for the harness seed (dot_config/harness/*, dot_local/share/crush-signal/*).
#
# Two harnesses ship in the seed: crush-signal (crush driven from Signal, model-pinned)
# and claude-code (Claude Code driven from the Claude app via Remote Control). The
# files have to agree with each other and with dot_config/crush/crush.json.tmpl or the
# harness silently runs the wrong model, or with no Signal channel. These assertions
# pin the couplings that a careless edit to any one file would break.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/create_harness.toml.tmpl"
HARNESS_ENV="$REPO_ROOT/dot_config/harness/crush-signal.env.tmpl"
# private_ (0600) matches the mode crush itself writes the file with. Without it
# chezmoi wants to chmod 644 on every apply, and because crush has also rewritten
# the contents it stops to ask "…has changed since chezmoi last wrote it?" —
# which wedges any non-interactive apply. Attribute order is create_ then private_.
MODEL_PIN="$REPO_ROOT/dot_local/share/crush-signal/create_private_crush.json.tmpl"
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

@test "harness: the crush model pin is private_ (0600) so apply never prompts" {
  # crush writes this file 0600. If the source is 0644 chezmoi has a pending chmod
  # forever, and since crush also edits the contents, apply blocks on a y/n prompt
  # with no TTY under launchd/systemd. Guard both the name and the committed mode.
  # The mode comes from the filename attribute, not the file's own bits — git
  # only records the exec bit, so 0600 can never be carried by the blob.
  case "$MODEL_PIN" in
    */create_private_crush.json.tmpl) ;;
    *) fail "model pin must be create_private_ (0600), got: $MODEL_PIN" ;;
  esac
}

@test "harness: rendered harness.toml is valid TOML with both seeded harnesses" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
d = tomllib.load(sys.stdin.buffer)
assert list(d[\"harness\"]) == [\"crush-signal\", \"claude-code\"], d[\"harness\"]
c = d[\"harness\"][\"crush-signal\"]
assert c[\"cmd\"].endswith(\"/.local/bin/crush\"), c[\"cmd\"]
cc = d[\"harness\"][\"claude-code\"]
assert cc[\"cmd\"].endswith(\"/.local/bin/claude\"), cc[\"cmd\"]
# Both run with permission prompts off, so neither may autostart on boot.
for name, h in d[\"harness\"].items():
    assert h[\"enabled\"] is False, name
'"
  [ "$status" -eq 0 ]
}

@test "harness: claude-code is Remote Control + skip-permissions, no Signal wiring" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # The phone drives this one through Remote Control, not the Signal channel: the
  # signal MCP in ~/.claude.json is wired WITHOUT --channel, and the cc prefix
  # belongs to crush-signal. An env_file here would be the tell that someone gave
  # claude a channel too — if that's ever wanted it needs its OWN prefix, because
  # two agents on one prefix both answer the same message.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
h = tomllib.load(sys.stdin.buffer)[\"harness\"][\"claude-code\"]
assert \"--remote-control\" in h[\"args\"], h[\"args\"]
assert \"--dangerously-skip-permissions\" in h[\"args\"], h[\"args\"]
assert h[\"workdir\"].endswith(\"/src\"), h[\"workdir\"]
assert \"env_file\" not in h, h
'"
  [ "$status" -eq 0 ]
}

@test "harness: crush-signal runs --yolo with the signal MCP opted in as a channel" {
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
  # Every cmd, not just the first: count the absolute ones against the total.
  total="$(printf '%s\n' "$output" | grep -c '^cmd = ')"
  absolute="$(printf '%s\n' "$output" | grep -c '^cmd = "/')"
  [ "$total" -ge 2 ]
  [ "$absolute" -eq "$total" ]
}

@test "harness: env_file repoints CRUSH_GLOBAL_DATA at the model-pin dir" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_ENV"
  [ "$status" -eq 0 ]
  # Must point at the dir holding create_crush.json.tmpl's target, or the pin is inert.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_ENV' | grep -c '^CRUSH_GLOBAL_DATA=/.*/\.local/share/crush-signal\$'"
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
