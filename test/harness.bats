#!/usr/bin/env bats
# Tests for the harness seed (dot_config/harness/*, dot_local/share/crush-signal/*).
#
# Two harnesses ship in the seed: crush-signal (crush driven from Signal, model-pinned)
# and claude-code (Claude Code driven from the Claude app via Remote Control). The
# files have to agree with each other and with dot_config/crush/crush.json.tmpl or the
# harness silently runs the wrong model, or with no Signal channel. These assertions
# pin the couplings that a careless edit to any one file would break.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/harness.toml.tmpl"
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

@test "harness: harness.toml is MANAGED (not create_) so edits reach every machine" {
  # This was create_ — seed-once — on the reasoning that harness's new-harness
  # TUI form rewrites it. That held, but the cost was worse: a create_ file is
  # never updated again, so every edit to the template reached NEW machines only.
  # tars sat on a 2026-07-26 copy whose harness names and profiles had drifted
  # completely from this template, and no amount of czu could reconcile it.
  #
  # The declared set has to win, because it is the only copy that propagates.
  # The TUI-rewrite problem is handled the way this repo handles every other
  # app-fought file: czu_reassert_targets in executable_czu-run.zsh. Deliberate
  # consequence: a harness created through the TUI does not survive a czu.
  [ -f "$HARNESS_TOML" ]
  case "$HARNESS_TOML" in
    */create_*) fail "harness.toml must NOT be create_ — it has to update on czu" ;;
  esac
}

@test "harness: czu reasserts harness.toml, since the TUI rewrites it" {
  # Managed-but-app-rewritten trips chezmoi's changed-since-last-write guard:
  # interactive apply prompts, scheduled apply silently skips. Without this the
  # switch away from create_ would trade one silent no-op for another.
  grep -q '"\$HOME/.config/harness/harness.toml"' \
    "$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
}

@test "harness: the crush model pin STAYS create_ (crush owns it outright)" {
  # Unchanged by the harness.toml switch. crush rewrites this on every model
  # change and nothing in it needs to propagate — it is per-machine state, not
  # declared config.
  case "$MODEL_PIN" in
    */create_private_crush.json.tmpl) ;;
    *) fail "crush model pin must stay create_private_, got: $MODEL_PIN" ;;
  esac
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

@test "harness: rendered harness.toml is valid TOML with all seeded harnesses" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
d = tomllib.load(sys.stdin.buffer)
assert list(d[\"harness\"]) == [\"crush-signal\", \"claude-code\", \"claude-headless\"], d[\"harness\"]
c = d[\"harness\"][\"crush-signal\"]
assert c[\"cmd\"].endswith(\"/.local/bin/crush\"), c[\"cmd\"]
cc = d[\"harness\"][\"claude-code\"]
assert cc[\"cmd\"].endswith(\"/.local/bin/claude\"), cc[\"cmd\"]
# All run with permission prompts off, so none may autostart on boot.
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

@test "harness: crush-signal opts into the switchboard channel too" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Without this opt-in the switchboard MCP's tools still work but its doorbell
  # notifications never reach the session — the queue fills silently. The
  # opt-in is CLI-only in the fork (no config key), so it must ride args.
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"--channels", "switchboard"'* ]]
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

@test "harness: the crush signal MCP renders identity-free" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Identity (account, operator, prefix) is resolved by signal-mcp from its
  # RUNTIME env, provisioned per-user by OpenBao — the render carries none of
  # it, so the same file is correct on every box and for every identity.
  run env -u SIGNAL_MCP_PREFIX bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"--channel"'* ]]
  [[ "$output" != *'"--account"'* ]]
  [[ "$output" != *'"--operator"'* ]]
  [[ "$output" != *'"--prefix"'* ]]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "harness: SIGNAL_MCP_* env never leaks into the crush render" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run env SIGNAL_MCP_PREFIX=cc SIGNAL_MCP_ACCOUNT=+15550001111 bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON'"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"cc"'* ]]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "harness: crush-signal's env file carries the cc opt-in" {
  # The opt-in must live in the env_file the harness daemon loads, or the
  # general-purpose agent silently starts answering every Signal message.
  grep -q '^SIGNAL_MCP_PREFIX=cc$' "$REPO_ROOT/dot_config/harness/crush-signal.env.tmpl"
}

@test "harness: the channel-enabled MCP servers are actually named 'signal' and 'switchboard'" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # crush matches --channels entries against MCP server names; a rename would
  # silently disable the channel.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON' | python3 -c '
import json,sys
mcp = json.load(sys.stdin)[\"mcp\"]
assert \"signal\" in mcp, sorted(mcp)
assert \"switchboard\" in mcp, sorted(mcp)
'"
  [ "$status" -eq 0 ]
}
