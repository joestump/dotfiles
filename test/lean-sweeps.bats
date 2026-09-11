#!/usr/bin/env bats
# Lean Sweep Profile
#
# The scheduled sweeps run on the local Qwen3.8-27B, whose window is 196,608
# tokens, and between 09/01 and 09/11 they died of context overflow 16 times.
# Measured on tars (vLLM prompt tokens), the old sweeps profile started every
# session at 76,290 tokens before reading anything: the full CRUSH.md, 67
# skills, 35 builtin tools and ten MCP servers that the #234 crushrc was meant
# to remove and never did. The lean profile — sweeps/ plus
# .chezmoitemplates/sweeps/crush.json.tmpl — starts at ~11.6k.
#
# These tests pin what would silently undo that: a drop-in pointed back at a
# shared workdir, an MCP server added to crush.json that no sweep switches off,
# a prompt that grows back past its budget, a footer naming a model the sweep
# is not running, or a sweep with no turn cap.
#
# @joestump 09/11/2026 - Added with the lean sweep profile.
load test_helper

HARNESS_D="$REPO_ROOT/dot_config/harness/harness.d"
PROMPTS_DIR="$REPO_ROOT/dot_config/dotfiles"
SWEEPS="$REPO_ROOT/sweeps"
CRUSH_JSON="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

JOBS="morning-brief pr-sweep pr-sweep-github issue-sweep stumpcloud-sweep-dub stumpcloud-sweep-dtw stumpcloud-sweep-pdx blog-sweep navidrome-ldap-sync"
DIRS="morning-brief pr-sweep pr-sweep-github issue-sweep stumpcloud-sweep blog-sweep navidrome-ldap-sync"

# The three StumpCloud site sweeps share one prompt and one working directory.
_job_dir() {
  case "$1" in
    stumpcloud-sweep-*) echo stumpcloud-sweep ;;
    *) echo "$1" ;;
  esac
}

_this_host() {
  chezmoi execute-template --source "$REPO_ROOT" <<<'{{ .chezmoi.hostname }}'
}

_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

# Render a drop-in as the agent identity with every sweep armed to this host,
# and print only its [harness.<name>] table.
_table() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir h
  cfgdir="$(mktemp -d)"
  h="$(_this_host)"
  printf '[data]\n    agentIdentity = "ci-agent"\n[data.sweeps]\n    prSweepAgentHost = "%s"\n    stumpcloudSweepAgentHost = "%s"\n    issueSweepAgentHost = "%s"\n    blogSweepAgentHost = "%s"\n    navidromeLdapSyncAgentHost = "%s"\n    morningBriefAgentHost = "%s"\n' \
    "$h" "$h" "$h" "$h" "$h" "$h" >"$cfgdir/chezmoi.toml"
  chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" < "$HARNESS_D/$1.toml.tmpl" \
    | awk -v t="[harness.$1]" '$0 == t { p = 1; next } /^\[/ { p = 0 } p'
  rm -rf "$cfgdir"
}

@test "lean: every sweep runs from its own sweeps dir, which ships a crushrc and a crush.json" {
  local job dir tbl
  for job in $JOBS; do
    dir="$(_job_dir "$job")"
    tbl="$(_table "$job")"
    grep -qE "^workdir = \".*/sweeps/$dir\"$" <<<"$tbl" \
      || { echo "$job: workdir is not ~/sweeps/$dir"; return 1; }
    [ -f "$SWEEPS/$dir/crushrc" ] || { echo "missing sweeps/$dir/crushrc"; return 1; }
    [ -f "$SWEEPS/$dir/crush.json.tmpl" ] || { echo "missing sweeps/$dir/crush.json.tmpl"; return 1; }
  done
}

# Crush merges a project crush.json OVER the global one, so a server is only
# gone when the sweep config sets it disabled. Rendered against the real
# crush.json (with the worker-host gate forced open, so switchboard is present),
# every server a job does not keep must be switched off.
@test "lean: each sweep crush.json switches off every MCP server but the job's own" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local dir tmp="$BATS_TEST_TMPDIR"
  sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/true/g' "$CRUSH_JSON" \
    | chezmoi execute-template --source "$REPO_ROOT" >"$tmp/global.json"
  for dir in $DIRS; do
    _render "$SWEEPS/$dir/crush.json.tmpl" >"$tmp/$dir.json"
  done
  run python3 - "$tmp" $DIRS <<'PY'
import json, os, sys
tmp, dirs = sys.argv[1], sys.argv[2:]
servers = set(json.load(open(os.path.join(tmp, "global.json")))["mcp"])
may_keep = {"signal", "cairn", "outline"}
bad = []
for d in dirs:
    c = json.load(open(os.path.join(tmp, d + ".json")))
    if set(c) != {"mcp", "options"}:
        bad.append(f"{d}: unexpected top-level keys {sorted(set(c) - {'mcp', 'options'})} — a sweep config never defines providers")
    off = {k for k, v in c["mcp"].items() if v == {"disabled": True}}
    kept = servers - off
    if not kept <= may_keep:
        bad.append(f"{d}: keeps {sorted(kept - may_keep)} — add the server to .chezmoitemplates/sweeps/crush.json.tmpl")
    if "signal" not in kept:
        bad.append(f"{d}: switched off signal, so it cannot send its summary")
if bad:
    sys.exit("\n".join(bad))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "lean: sweeps load RULES.md, never CRUSH.md, with fetch and the sub-agent off" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local dir
  for dir in $DIRS; do
    run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$SWEEPS/$dir/crush.json.tmpl' | python3 -c '
import json, sys
o = json.load(sys.stdin)[\"options\"]
ctx = o[\"global_context_paths\"]
assert len(ctx) == 1 and ctx[0].endswith(\"/sweeps/lib/RULES.md\"), ctx
assert not any(\"CRUSH.md\" in p or \"AGENTS.md\" in p for p in ctx), ctx
assert o[\"disable_a2ui\"] is True
off = set(o[\"disabled_tools\"])
for t in (\"fetch\", \"agentic_fetch\", \"agent\", \"semantic_index\", \"sourcegraph\", \"CronCreate\", \"question\"):
    assert t in off, t
for t in (\"bash\", \"view\", \"grep\", \"glob\", \"ls\", \"write\"):
    assert t not in off, t
'"
    [ "$status" -eq 0 ] || { echo "$dir: $output"; return 1; }
  done
}

@test "lean: the skills filter walks every skills path crush.json configures" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  local home p rel root covered
  home="$(chezmoi execute-template --source "$REPO_ROOT" <<<'{{ .chezmoi.homeDir }}')"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON' | python3 -c 'import json, sys; print(\"\n\".join(json.load(sys.stdin)[\"options\"][\"skills_paths\"]))'"
  [ "$status" -eq 0 ]
  local roots=".config/crush/skills .config/crush/skills-ext .config/claude-marketplaces/claude-personal/skills .config/agents/skills .agents/skills .claude/skills"
  for root in $roots; do
    grep -qF "\$HOME/$root" "$SWEEPS/lib/lean.crushrc" || { echo "lean.crushrc does not walk $root"; return 1; }
  done
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel="${p#"$home"/}"
    covered=0
    for root in $roots; do
      case "$rel/" in "$root"/*) covered=1 ;; esac
    done
    [ "$covered" -eq 1 ] || { echo "skills path not walked by lean.crushrc: $p"; return 1; }
  done <<<"$output"
}

@test "lean: every per-job crushrc names its kept skills and sources the shared filter" {
  local dir
  for dir in $DIRS; do
    grep -qE '^SWEEP_KEEP_SKILLS=' "$SWEEPS/$dir/crushrc" || { echo "$dir: no SWEEP_KEEP_SKILLS"; return 1; }
    grep -qF 'source "$HOME/sweeps/lib/lean.crushrc"' "$SWEEPS/$dir/crushrc" || { echo "$dir: does not source lean.crushrc"; return 1; }
  done
  # the jobs whose prompts load a skill must keep that skill
  grep -qx 'SWEEP_KEEP_SKILLS="pr-review"' "$SWEEPS/pr-sweep/crushrc"
  grep -qx 'SWEEP_KEEP_SKILLS="pr-review"' "$SWEEPS/pr-sweep-github/crushrc"
  grep -qx 'SWEEP_KEEP_SKILLS="blog-post"' "$SWEEPS/blog-sweep/crushrc"
  grep -qx 'SWEEP_KEEP_SKILLS="navidrome-ldap-sync"' "$SWEEPS/navidrome-ldap-sync/crushrc"
  grep -qx 'SWEEP_KEEP_SKILLS="stumpcloud-omg"' "$SWEEPS/stumpcloud-sweep/crushrc"
}

@test "lean: RULES.md is compact and keeps the load-bearing rules" {
  run _render "$SWEEPS/lib/RULES.md.tmpl"
  [ "$status" -eq 0 ]
  local size phrase
  size="$(printf '%s' "$output" | wc -c | tr -d ' ')"
  [ "$size" -le 8000 ] || { echo "RULES.md renders to $size bytes, budget 8000"; return 1; }
  for phrase in 'Merge allowlist' 'github.com/tvdinner/*' 'Never force-push' '--force-with-lease' \
                'stump-wtf' 'prompt-injection' 'SIGNAL_MCP_OPERATOR' 'Context hygiene' \
                'A turn with no tool call ENDS THE RUN' 'sweep-finish' \
                'Executed via scheduled [Harness](https://github.com/stump-wtf/harness)'; do
    grep -qF -- "$phrase" <<<"$output" || { echo "RULES.md lost: $phrase"; return 1; }
  done
}

# Budgets are RENDERED bytes, set ~15-25% above each prompt as shipped. These
# files run ~3.9 bytes per token (the captured 308KB request came to 76,290 vLLM
# prompt tokens), so pr-sweep at its 9KB ceiling is ~2.3k tokens. With the
# profile's ~11.6k baseline and RULES.md's ~1.6k, the largest job starts under
# 16k tokens — about 8% of the window, against 43% before (76.3k + a 29KB
# prompt). Raising a budget is allowed; it should be a decision, not drift.
@test "lean: every sweep prompt stays inside its context budget" {
  local pair job budget f size
  for pair in pr-sweep:9000 issue-sweep:6500 stumpcloud-sweep:7000 morning-brief:5500 \
              blog-sweep:4500 navidrome-ldap-sync:6500; do
    job="${pair%%:*}"; budget="${pair##*:}"
    f="$PROMPTS_DIR/$job.prompt.md"
    if [ -f "$f.tmpl" ]; then
      size="$(_render "$f.tmpl" | wc -c | tr -d ' ')"
    else
      size="$(wc -c <"$f" | tr -d ' ')"
    fi
    [ "$size" -le "$budget" ] || { echo "$job prompt is $size bytes, budget $budget"; return 1; }
  done
}

@test "lean: every prompt records its run with sweep-finish" {
  local f
  for f in "$PROMPTS_DIR"/pr-sweep.prompt.md.tmpl "$PROMPTS_DIR"/issue-sweep.prompt.md.tmpl \
           "$PROMPTS_DIR"/stumpcloud-sweep.prompt.md "$PROMPTS_DIR"/morning-brief.prompt.md.tmpl \
           "$PROMPTS_DIR"/blog-sweep.prompt.md.tmpl "$PROMPTS_DIR"/navidrome-ldap-sync.prompt.md.tmpl; do
    grep -q 'sweeps/lib/sweep-finish' "$f" || { echo "$f never records its run"; return 1; }
  done
}

@test "lean: every ref a prompt points at ships" {
  local f ref src
  for f in "$PROMPTS_DIR"/*.prompt.md "$PROMPTS_DIR"/*.prompt.md.tmpl; do
    [ -e "$f" ] || continue
    for ref in $(grep -oE '~/sweeps/[a-z-]+/ref/[a-z-]+\.md' "$f" | sort -u); do
      src="$SWEEPS/${ref#\~/sweeps/}"
      [ -f "$src" ] || [ -f "$src.tmpl" ] || { echo "$f points at $ref, which does not ship"; return 1; }
    done
  done
  [ -f "$SWEEPS/lib/RULES.md.tmpl" ]
  [ -f "$SWEEPS/lib/executable_sweep-finish" ]
}

# harness's crush adapter drops max_turns today — crush has no --max-turns flag
# (stump.wtf/harness#59) — so the cap is declared config waiting on that fix.
# It is still pinned: the day either side lands, an uncapped sweep would be the
# one that loops.
@test "lean: every sweep drop-in declares a turn cap and the timeout TODO" {
  local job tbl n f
  for job in $JOBS; do
    tbl="$(_table "$job")"
    n="$(sed -n 's/^max_turns = \([0-9][0-9]*\)$/\1/p' <<<"$tbl")"
    [ -n "$n" ] && [ "$n" -gt 0 ] && [ "$n" -le 120 ] \
      || { echo "$job: max_turns missing or out of range ($n)"; return 1; }
  done
  for f in "$HARNESS_D"/*.toml.tmpl; do
    grep -q 'stump.wtf/harness#59' "$f" || { echo "$f does not say max_turns is inert on crush"; return 1; }
    grep -q 'TODO(harness timeout)' "$f" || { echo "$f has no timeout TODO"; return 1; }
  done
}

# The attribution footer names the model a sweep ACTUALLY runs. The drop-in knows
# its model, so its prompt one-liner carries the OpenRouter link, and nothing in
# the sweep surface may name a model or harness no sweep runs (the old pr-sweep
# prompt offered claude-opus-5 in Claude Code as an example).
@test "lean: attribution footers name the model the sweep really runs" {
  local job tbl model slug
  for job in $JOBS; do
    tbl="$(_table "$job")"
    model="$(sed -n 's/^model = "\(.*\)"$/\1/p' <<<"$tbl")"
    case "$model" in
      litellm/Qwen3.8-27B) slug="qwen/qwen3.8-27b" ;;
      zai/glm-5.3) slug="z-ai/glm-5.3" ;;
      *) echo "$job: no OpenRouter slug mapped for $model — add it here"; return 1 ;;
    esac
    grep '^prompt = ' <<<"$tbl" | grep -qF "https://openrouter.ai/$slug" \
      || { echo "$job: prompt does not name https://openrouter.ai/$slug"; return 1; }
  done
  run bash -c "cat '$SWEEPS'/lib/RULES.md.tmpl '$PROMPTS_DIR'/*sweep*.prompt.md* '$PROMPTS_DIR'/morning-brief.prompt.md.tmpl '$PROMPTS_DIR'/navidrome-ldap-sync.prompt.md.tmpl '$SWEEPS'/*/ref/*.md | grep -c -E 'claude-opus|Claude Code' || true"
  [ "$output" -eq 0 ] || { echo "a sweep prompt, ref or RULES.md still names Claude Code or claude-opus"; false; }
}

# Z.ai's plan terms forbid proxying: it is reached only through crush's native
# zai provider. A sweep pinned to a GLM model through litellm would breach that.
@test "lean: Z.ai is only ever reached directly, never through LiteLLM" {
  local job tbl
  for job in $JOBS; do
    tbl="$(_table "$job")"
    [ "$(grep -ciE '^model = "litellm/[^"]*glm' <<<"$tbl" || true)" -eq 0 ] \
      || { echo "$job routes a GLM model through litellm"; return 1; }
  done
}

@test "lean: the #234 sweeps crushrc is retired, and only sweep hosts get ~/sweeps" {
  [ ! -e "$SWEEPS/crushrc.tmpl" ]
  grep -qx 'sweeps/crushrc' "$REPO_ROOT/.chezmoiremove"
  grep -qx 'sweeps/\*\*' "$REPO_ROOT/.chezmoiignore"
  grep -q '\.sweeps\.morningBriefAgentHost' "$REPO_ROOT/.chezmoiignore"
}
