#!/usr/bin/env bats
# Difficulty Lanes
#
# .switchboard.lanes in .chezmoidata.yaml declares which Crush worker drains
# which Switchboard lane queue (stump.wtf/switchboard ADR-0025). A worker is a
# harness table, an env file, a pin dir and a czu reassert entry, and the four
# only work together: a worker with no pin runs crush's fallback model (see
# test/harness.bats), and a pin aimed at the wrong endpoint drains the wrong
# queue. These tests pin those couplings, the one-host rule that makes each
# handoff run exactly once, and the provider rules.
#
# @joestump 09/11/2026 - Added with the difficulty lanes.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/harness.toml.tmpl"
CZU_RUN="$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"

# Evaluate a template against the repo's own data.
_q() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" <<<"$1"
}

# One line per worker: name|queue|provider|model|endpointEnv
_workers() {
  _q '{{ range $l := .switchboard.lanes }}{{ range $w := $l.workers }}{{ $w.name }}|{{ $l.queue }}|{{ $w.provider }}|{{ $w.model }}|{{ $l.endpointEnv }}
{{ end }}{{ end }}' | sed '/^$/d'
}

# Render harness.toml as identity $1 with the lane host set to $2.
_render_toml() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir rc
  cfgdir="$(mktemp -d)"
  printf '[data]\n    agentIdentity = "%s"\n[data.switchboard]\n    laneHost = "%s"\n' "$1" "$2" >"$cfgdir/chezmoi.toml"
  chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" < "$HARNESS_TOML"
  rc=$?
  rm -rf "$cfgdir"
  return $rc
}

@test "lanes: the queues are the lanes Switchboard routes, and hold has no worker" {
  run _q '{{ range .switchboard.lanes }}{{ .queue }} {{ end }}'
  [ "$status" -eq 0 ]
  [ "$output" = "lane-s lane-m lane-l lane-vision triage " ]
  [ -n "$(_q '{{ .switchboard.laneHost }}')" ]
}

@test "lanes: LiteLLM carries only the local Qwen; Z.ai and Hyper stay native" {
  # Z.ai's plan terms forbid proxying it, and LiteLLM's lane aliases were
  # reverted, so litellm means ai01's Qwen and nothing else.
  local name queue provider model env
  while IFS='|' read -r name queue provider model env; do
    case "$provider" in
      litellm) [ "$model" = "Qwen3.8-27B" ] || { echo "$name routes $model through litellm"; return 1; } ;;
      zai|hyper) ;;
      *) echo "$name: unexpected provider $provider"; return 1 ;;
    esac
  done < <(_workers)
}

@test "lanes: every worker ships an env file, a pin and a czu reassert entry" {
  local name queue provider model env dir declared
  declared=" $(_workers | cut -d'|' -f1 | tr '\n' ' ') "
  [ "$declared" != "  " ]
  for name in $declared; do
    [ -f "$REPO_ROOT/dot_config/harness/$name.env.tmpl" ] || { echo "$name has no env file"; return 1; }
    [ -f "$REPO_ROOT/dot_local/share/$name/private_crush.json.tmpl" ] || { echo "$name has no pin"; return 1; }
    grep -qF "\"\$HOME/.local/share/$name/crush.json\"" "$CZU_RUN" || { echo "$name has no czu reassert entry"; return 1; }
  done
  # And no orphans: a lane file whose worker was removed from the data would
  # fail to render (the pin partial refuses an undeclared name).
  for dir in "$REPO_ROOT"/dot_local/share/crush-lane-* "$REPO_ROOT"/dot_local/share/crush-triage; do
    [ -e "$dir" ] || continue
    name="$(basename "$dir")"
    [[ "$declared" == *" $name "* ]] || { echo "orphan lane pin: $name"; return 1; }
  done
}

@test "lanes: each pin runs its worker's model on its own lane's endpoint" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local name queue provider model env
  while IFS='|' read -r name queue provider model env; do
    chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_local/share/$name/private_crush.json.tmpl" \
      | python3 -c '
import json, sys
name, provider, model, env = sys.argv[1:]
d = json.load(sys.stdin)
want = {"model": model, "provider": provider}
assert d["models"]["large"] == want and d["models"]["small"] == want, (name, d["models"])
sb = d["mcp"]["switchboard"]
assert sb["url"] == "$" + env + "_URL", (name, sb["url"])
assert sb["headers"]["Authorization"] == "Bearer $" + env + "_API_KEY", (name, sb["headers"])
assert sb["disabled"] is False, name
' "$name" "$provider" "$model" "$env" || { echo "bad pin: $name"; return 1; }
  done < <(_workers)
}

@test "lanes: each queue has its own endpoint, apart from the pool's" {
  # Two queues on one endpoint, or a lane on the crush-switchboard pool's
  # endpoint, would hand one todo to workers of different lanes.
  run _q '{{ range .switchboard.lanes }}{{ .endpointEnv }}
{{ end }}'
  [ "$status" -eq 0 ]
  [ "$(sed '/^$/d' <<<"$output" | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 ]
  [ "$(grep -c '^SWITCHBOARD_CRUSH$' <<<"$output" || true)" -eq 0 ]
}

@test "lanes: env files point CRUSH_GLOBAL_DATA at the worker's own dir" {
  local name queue provider model env
  while IFS='|' read -r name queue provider model env; do
    chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_config/harness/$name.env.tmpl" \
      | grep -qE "^CRUSH_GLOBAL_DATA=/.*/\.local/share/$name\$" || { echo "$name env points elsewhere"; return 1; }
  done < <(_workers)
}

@test "lanes: the lane host's agent login declares every worker, in both profiles" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local toml
  toml="$BATS_TEST_TMPDIR/harness.toml"
  _render_toml ci-agent "$(_q '{{ .chezmoi.hostname }}')" >"$toml"
  _workers | python3 -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for line in sys.stdin:
    name, queue = line.strip().split("|")[:2]
    h = d["harness"][name]
    assert h["harness"] == "crush", name
    assert h["args"] == ["--yolo", "--channels", "switchboard"], (name, h["args"])
    assert h["env_file"].endswith("/.config/harness/" + name + ".env"), (name, h["env_file"])
    assert h["enabled"] is False and h["restart"] == "on-failure", name
    assert queue in h["description"], (name, h["description"])
    for p in ("default", "full"):
        assert name in d["profile"][p]["harnesses"], (name, p)
' "$toml"
}

@test "lanes: a human login, or any other host, declares no lane worker" {
  local this
  this="$(_q '{{ .chezmoi.hostname }}')"
  run _render_toml ci "$this"
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^\[harness\.crush-(lane-|triage)' <<<"$output" || true)" -eq 0 ]
  run _render_toml ci-agent "not-$this"
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^\[harness\.crush-(lane-|triage)' <<<"$output" || true)" -eq 0 ]
  [ "$(grep -c 'difficulty lanes"' <<<"$output" || true)" -eq 0 ]
}
