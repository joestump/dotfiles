#!/usr/bin/env bats
# Tests for the .switchboard.workerHosts gate — which machines get the switchboard MCP.
#
# The MCP is a WORKER capability: an agent holding it receives doorbells and is
# expected to claim, work and complete the todos they carry. A host that holds it
# and never drains is worse than one that never had it — todos route there, sit
# unclaimed, and the queue reads as backed up while the real workers are idle.
#
# That is what happened. Joe's laptop carried the Claude Code entry because the
# merge script added it wherever the credential resolved, and its endpoint
# accumulated 62 todos an interactive session was never going to touch. It looked
# like a Switchboard outage and was not one.
#
# So both templates gate on the same data key, and these tests pin the three
# things that would silently undo it.
load test_helper

DATA="$REPO_ROOT/.chezmoidata.yaml"
CRUSH="$REPO_ROOT/dot_config/crush/crush.json.tmpl"
MERGE="$REPO_ROOT/.chezmoiscripts/run_after_43-claude-code-mcp-merge.sh.tmpl"

# Render a template with .chezmoi.hostname forced, by substituting the gate's
# condition. Rendering as another host is not something chezmoi offers directly,
# and the alternative — trusting the gate by reading it — is what a test is for.
_render_as_worker() { sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/true/g' "$1" \
  | chezmoi execute-template --source "$REPO_ROOT"; }
_render_as_other()  { sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/false/g' "$1" \
  | chezmoi execute-template --source "$REPO_ROOT"; }

@test "switchboard: the worker host list is declared and non-empty" {
  run python3 -c "
import yaml,sys
d=yaml.safe_load(open('$DATA'))
hosts=(d.get('switchboard') or {}).get('workerHosts') or []
assert hosts, 'workerHosts is empty — that removes the MCP fleet-wide'
print(' '.join(hosts))
"
  [ "$status" -eq 0 ]
  # kitt and tars are the boxes that actually run harness worker pools.
  [[ "$output" == *kitt* ]]
  [[ "$output" == *tars* ]]
}

@test "switchboard: crush.json omits the MCP off a worker host, and stays valid JSON" {
  # The comma placement is the fragile part: the entry before switchboard must not
  # be left with a trailing comma when this one is absent. A gate that produces
  # invalid JSON fails Crush at startup with a message about providers, not about
  # the MCP — so this asserts the PARSE, not just the absence.
  run bash -c "_r() { sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/false/g' '$CRUSH' | chezmoi execute-template --source '$REPO_ROOT'; }; _r | python3 -c '
import json,sys
d=json.load(sys.stdin)
m=d.get(\"mcp\") or d.get(\"mcpServers\") or {}
assert \"switchboard\" not in m, \"switchboard MCP rendered on a non-worker host\"
print(\"ok\", len(m), \"servers\")
'"
  [ "$status" -eq 0 ]
}

@test "switchboard: crush.json KEEPS the MCP on a worker host, and stays valid JSON" {
  # The inverse matters just as much: a gate that removes the entry everywhere
  # would pass the test above and silently disarm both real workers.
  run bash -c "_r() { sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/true/g' '$CRUSH' | chezmoi execute-template --source '$REPO_ROOT'; }; _r | python3 -c '
import json,sys
d=json.load(sys.stdin)
m=d.get(\"mcp\") or d.get(\"mcpServers\") or {}
assert \"switchboard\" in m, \"switchboard MCP missing on a worker host\"
assert m[\"switchboard\"][\"url\"] == \"\$SWITCHBOARD_CRUSH_URL\", m[\"switchboard\"]
print(\"ok\")
'"
  [ "$status" -eq 0 ]
}

@test "switchboard: the Claude Code merge DELETES a stale entry off a worker host" {
  # Emptying the two halves only skips the ADD. A machine that was a worker before
  # this gate existed would otherwise keep a live, doorbell-receiving entry forever
  # — which is the exact state the gate exists to end.
  run bash -c "sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/false/g' '$MERGE' | chezmoi execute-template --source '$REPO_ROOT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"del(.switchboard)"* ]]
  printf '%s\n' "$output" | grep -qE '^SB=""'
  printf '%s\n' "$output" | grep -qE '^SB_URL=""'
}

@test "switchboard: the Claude Code merge still bakes the entry on a worker host" {
  run bash -c "sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/true/g' '$MERGE' | chezmoi execute-template --source '$REPO_ROOT'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'SWITCHBOARD_CLAUDE_CODE_API_KEY'
  printf '%s\n' "$output" | grep -q 'SWITCHBOARD_CLAUDE_CODE_URL'
  # The delete branch must be unreachable there, or a worker would lose its entry.
  [[ "$output" == *"elif false then del(.switchboard)"* ]]
}
