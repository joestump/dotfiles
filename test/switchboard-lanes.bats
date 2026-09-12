#!/usr/bin/env bats
# Difficulty Lanes
#
# .switchboard.lanes in .chezmoidata.yaml declares which Crush worker drains
# which Switchboard lane queue (stump.wtf/switchboard ADR-0025). A worker is a
# harness table, an env file, a pin dir and a czu reassert entry, and the four
# only work together: a worker with no pin runs crush's fallback model (see
# test/harness.bats), and a pin aimed at the wrong endpoint drains the wrong
# queue. These tests pin those couplings, the one-host rule that makes each
# handoff run exactly once, the provider rules, and the arming rule: a lane
# renders nothing until its credentials exist.
#
# @joestump 09/11/2026 - Added with the difficulty lanes.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/harness.toml.tmpl"
RELOAD="$REPO_ROOT/.chezmoiscripts/run_onchange_after_52-harness-reload.sh.tmpl"
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

# A fake Vault Agent secrets file carrying credentials for the given endpoint
# prefixes, in the file's own `export KEY='value'` shape. Prints its path.
_secrets() {
  local f p
  f="$(mktemp "$BATS_TEST_TMPDIR/secrets.XXXXXX")"
  for p in "$@"; do
    printf "export %s_URL='https://switchboard.invalid/mcp/fixture'\nexport %s_API_KEY='fixture'\n" "$p" "$p" >>"$f"
  done
  echo "$f"
}

_all_prefixes() { _q '{{ range .switchboard.lanes }}{{ .endpointEnv }} {{ end }}'; }

# Render harness.toml as identity $1, lane host $2, secrets file $3.
_render_toml() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir rc
  cfgdir="$(mktemp -d)"
  printf '[data]\n    agentIdentity = "%s"\n[data.switchboard]\n    laneHost = "%s"\n    laneSecretsFile = "%s"\n' "$1" "$2" "$3" >"$cfgdir/chezmoi.toml"
  chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" < "$HARNESS_TOML"
  rc=$?
  rm -rf "$cfgdir"
  return $rc
}

_lane_tables() { grep -cE '^\[harness\.crush-(lane-|triage)' <<<"$1" || true; }

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
  local name dir declared
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

@test "lanes: the armed lane host declares every worker, in both profiles" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local toml
  toml="$BATS_TEST_TMPDIR/harness.toml"
  # shellcheck disable=SC2046
  _render_toml ci-agent "$(_q '{{ .chezmoi.hostname }}')" "$(_secrets $(_all_prefixes))" >"$toml"
  _workers | python3 -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for line in sys.stdin:
    name, queue = line.strip().split("|")[:2]
    h = d["harness"][name]
    assert h["harness"] == "crush", name
    # The channel args are what this test owns; the store flag that follows is
    # asserted in full by "every armed lane worker gets its own session store".
    # Freezing the whole list here would fail on any future arg without saying
    # anything useful about the channel wiring.
    assert h["args"][:3] == ["--yolo", "--channels", "switchboard"], (name, h["args"])
    assert h["env_file"].endswith("/.config/harness/" + name + ".env"), (name, h["env_file"])
    assert h["enabled"] is False and h["restart"] == "on-failure", name
    assert queue in h["description"], (name, h["description"])
    for p in ("default", "full"):
        assert name in d["profile"][p]["harnesses"], (name, p)
' "$toml"
}

@test "lanes: every armed lane worker gets its own session store" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # Same reasoning as crush-signal and the pool: a lane worker also runs in
  # ~/src, so without --data-dir all seven would share ~/src/.crush/crush.db and
  # `harness logs` could attribute none of them. The naming assertion is the one
  # that survives a rename - seven distinct-but-wrong paths would pass a bare
  # uniqueness check while attributing sessions to the wrong harness.
  local toml
  toml="$BATS_TEST_TMPDIR/lanes-armed.toml"
  # shellcheck disable=SC2046
  _render_toml ci-agent "$(_q '{{ .chezmoi.hostname }}')" "$(_secrets $(_all_prefixes))" >"$toml"
  python3 -c "
import tomllib
d = tomllib.load(open('$toml', 'rb'))
seen = {}
for name, h in d['harness'].items():
    if not (name.startswith('crush-lane-') or name == 'crush-triage'):
        continue
    args = h['args']
    assert '--data-dir' in args, ('no --data-dir', name, args)
    p = args[args.index('--data-dir') + 1]
    assert p.startswith('/'), ('not absolute', name, p)
    assert p.endswith('/data'), ('not a /data dir', name, p)
    assert p.rsplit('/', 2)[-2] == name, ('store not named for harness', name, p)
    assert p not in seen, ('two lanes share a store', name, seen.get(p), p)
    seen[p] = name
    # Only the bookkeeping moves; lane workers still work in the repo tree.
    assert h['workdir'].endswith('/src'), ('workdir moved', name, h['workdir'])
assert len(seen) == 7, ('expected all seven lane workers', sorted(seen.values()))
"
}

@test "lanes: a human login, or any other host, declares no lane worker" {
  local this secrets
  this="$(_q '{{ .chezmoi.hostname }}')"
  # shellcheck disable=SC2046
  secrets="$(_secrets $(_all_prefixes))"
  run _render_toml ci "$this" "$secrets"
  [ "$status" -eq 0 ]
  [ "$(_lane_tables "$output")" -eq 0 ]
  run _render_toml ci-agent "not-$this" "$secrets"
  [ "$status" -eq 0 ]
  [ "$(_lane_tables "$output")" -eq 0 ]
  [ "$(grep -c 'difficulty lanes"' <<<"$output" || true)" -eq 0 ]
}

# Merging the lanes must be safe before switchboard ships them: a lane worker
# whose endpoint was never vended starts green and drains nothing, and one in
# the autostart profile would start that way on the next daemon restart. So
# with no credentials, harness.toml must be byte-identical to a render with the
# lanes switched off entirely.
@test "lanes: with no credentials, nothing renders and the rest is unchanged" {
  local this off empty
  this="$(_q '{{ .chezmoi.hostname }}')"
  off="$(_render_toml ci-agent "" "/nonexistent/secrets.env")"
  [ "$(_lane_tables "$off")" -eq 0 ]
  # No secrets file at all.
  run _render_toml ci-agent "$this" "/nonexistent/secrets.env"
  [ "$status" -eq 0 ]; [ "$output" = "$off" ]
  # A secrets file carrying only today's keys.
  run _render_toml ci-agent "$this" "$(_secrets SWITCHBOARD_CRUSH SWITCHBOARD_CLAUDE_CODE)"
  [ "$status" -eq 0 ]; [ "$output" = "$off" ]
  # A URL with an empty key, and a key with no URL, are both still unarmed.
  empty="$(_secrets)"
  printf "export SWITCHBOARD_LANE_S_URL='https://switchboard.invalid/mcp/x'\nexport SWITCHBOARD_LANE_S_API_KEY=''\nexport SWITCHBOARD_LANE_M_API_KEY='fixture'\n" >"$empty"
  run _render_toml ci-agent "$this" "$empty"
  [ "$status" -eq 0 ]; [ "$output" = "$off" ]
}

@test "lanes: each lane arms on its own credentials only" {
  local this
  this="$(_q '{{ .chezmoi.hostname }}')"
  run _render_toml ci-agent "$this" "$(_secrets SWITCHBOARD_LANE_M)"
  [ "$status" -eq 0 ]
  [ "$(_lane_tables "$output")" -eq 2 ]
  grep -qE '^\[harness\.crush-lane-m-zai\]' <<<"$output"
  grep -qE '^\[harness\.crush-lane-m-hyper\]' <<<"$output"
  grep -qE '^harnesses = .*"crush-lane-m-hyper"' <<<"$output"
  [ "$(grep -cE '^harnesses = .*"crush-(lane-s|lane-l|lane-vision|triage)"' <<<"$output" || true)" -eq 0 ]
}

@test "lanes: arming a lane re-fires the harness reload script" {
  # Credentials change the rendered harness.toml, not its template, so the
  # template hash alone would never reload the daemon.
  grep -q 'armed lanes: {{ includeTemplate "harness/armed-lanes.tmpl" . | trim }}' "$RELOAD"
}
