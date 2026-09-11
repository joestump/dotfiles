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
# So crush.json gates on that data key, and these tests pin the things that would
# silently undo it. Claude Code is no longer gated at all: its merge script drops
# the entry on every host, because no Claude Code queue worker exists anywhere.
#
# @joestump 09/11/2026 - The Claude Code half went from "worker hosts only" to
#   "nowhere" when the claude-headless pool was retired.
load test_helper

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
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Read the key THROUGH chezmoi rather than parsing the YAML directly: it is what
  # the two templates actually see, it needs no PyYAML (CI's python has none), and
  # a key renamed or moved fails here instead of passing against a stale path.
  run chezmoi execute-template --source "$REPO_ROOT" \
    '{{ .switchboard.workerHosts | join " " }}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]   # empty removes the MCP fleet-wide, silently
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

@test "switchboard: the Claude Code merge DROPS the entry on every host, workers included" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # #239 shipped a del() inside the DESIRED object believing that removed it. It did
  # not: mcp_merge is additive, so a key absent from `desired` is left alone in the
  # live config. The laptop kept its entry through a full apply that reported
  # "mcpServers already current". mcp_drop is the only thing that edits the live
  # config, so that is what this asserts.
  #
  # Rendered both ways: kitt and tars carried a baked entry while claude-headless
  # drained it, and they are exactly the boxes a worker-hosts-only drop would miss.
  local gate
  for gate in true false; do
    run bash -c "sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/$gate/g' '$MERGE' | chezmoi execute-template --source '$REPO_ROOT'"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qE '^mcp_drop .*"\$CJ" .*\bswitchboard\b' \
      || { echo "no switchboard drop with gate=$gate"; return 1; }
  done
}

@test "switchboard: the Claude Code merge never bakes a switchboard entry" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # A bake here would be undone by the drop above on the same apply, so the pair
  # would flap the entry in and out of ~/.claude.json every run. Counting
  # assertions, not `! grep`, which set -e ignores mid-test.
  run chezmoi execute-template --source "$REPO_ROOT" < "$MERGE"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'SWITCHBOARD_CLAUDE_CODE' <<<"$output" || true)" -eq 0 ]
  [ "$(grep -c '\.switchboard = ' <<<"$output" || true)" -eq 0 ]
}
