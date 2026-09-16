#!/usr/bin/env bats
# Lean Worker Capability Manifests
#
# The always-on Crush workers — the crush-signal and crush-switchboard pool
# and the difficulty lanes — each get their config from a CRUSH_GLOBAL_DATA
# pin that merges OVER the global ~/.config/crush/crush.json. A pin that names
# only a model therefore inherits every MCP server the global config enables.
# Measured on tars against litellm/Qwen3.8-27B, that was 81,309 prompt tokens
# in a pool worker's first turn, 36,007 of them tool schemas for eleven
# servers, five of which the pool's whole recorded history never called once.
#
# These tests pin what would silently undo the fix: a pin that stops switching
# a server off, a server added to crush.json that no manifest knows about, a
# lane that drops its own switchboard endpoint or its way to report back, or a
# pin that grows a providers block it has no business holding.
#
# The sweep half of the same argument is test/lean-sweeps.bats.
#
# @joestump 09/16/2026 - Added with the worker capability manifests.
load test_helper

CRUSH_JSON="$REPO_ROOT/dot_config/crush/crush.json.tmpl"
LEAN="$REPO_ROOT/.chezmoitemplates/harness/worker-lean.tmpl"
POOL_PINS="crush-signal crush-switchboard"

_need() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
}

# The global MCP server names, with the worker-host gate forced open so
# switchboard is present whatever host the suite runs on.
_global_servers() {
  sed -E 's/has \.chezmoi\.hostname \.switchboard\.workerHosts/true/g' "$CRUSH_JSON" \
    | chezmoi execute-template --source "$REPO_ROOT" \
    | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin)["mcp"])))'
}

# Every pin dir under dot_local/share that holds a crush.json template.
_pin_dirs() {
  local d
  for d in "$REPO_ROOT"/dot_local/share/*/; do
    [ -f "$d/private_crush.json.tmpl" ] && basename "$d"
  done
}

_render_pin() {
  chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_local/share/$1/private_crush.json.tmpl"
}

# Every worker name declared in .switchboard.lanes.
_lane_workers() {
  chezmoi execute-template --source "$REPO_ROOT" \
    <<<'{{ range $l := .switchboard.lanes }}{{ range $w := $l.workers }}{{ $w.name }}
{{ end }}{{ end }}' | sed '/^$/d'
}

@test "workers: the manifest partial knows every MCP server the global config enables" {
  _need
  # worker-lean.tmpl can only switch off a server it names. A server added to
  # crush.json and not added here rides into every worker enabled.
  local declared missing s
  declared="$(sed -n 's/^{{- \$servers := list \(.*\) -}}$/\1/p' "$LEAN" | tr -d '"')"
  [ -n "$declared" ] || { echo "could not find \$servers in $LEAN"; return 1; }
  missing=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case " $declared " in *" $s "*) ;; *) missing="$missing $s" ;; esac
  done < <(_global_servers)
  [ -z "$missing" ] || { echo "worker-lean.tmpl \$servers is missing:$missing"; return 1; }
}

@test "workers: every pin switches off every global server it does not keep" {
  _need
  local tmp="$BATS_TEST_TMPDIR" pin
  _global_servers >"$tmp/servers.txt"
  for pin in $(_pin_dirs); do
    _render_pin "$pin" >"$tmp/$pin.json" || { echo "$pin: pin failed to render"; return 1; }
  done
  run python3 - "$tmp" $(_pin_dirs) <<'PY'
import json, os, sys
tmp, pins = sys.argv[1], sys.argv[2:]
servers = set(open(os.path.join(tmp, "servers.txt")).read().split())
# The only servers a worker may keep, and why: switchboard to claim its todos,
# gitea for the repo work, cairn for the handoff artifact, signal to report,
# chrome-devtools for the vision lane alone.
may_keep = {"switchboard", "gitea", "cairn", "signal", "chrome-devtools"}
bad = []
for p in pins:
    c = json.load(open(os.path.join(tmp, p + ".json")))
    extra = set(c) - {"$schema", "mcp", "models", "lsp"}
    if extra:
        bad.append(f"{p}: unexpected top-level keys {sorted(extra)} — a worker pin never defines providers or options")
    if "mcp" not in c:
        bad.append(f"{p}: no mcp block, so it inherits all of {sorted(servers)}")
        continue
    off = {k for k, v in c["mcp"].items() if v.get("disabled") is True}
    kept = servers - off
    if not kept <= may_keep:
        bad.append(f"{p}: keeps {sorted(kept - may_keep)} — add it to the lane's mcp list in .chezmoidata.yaml, or stop keeping it")
    if "signal" not in kept:
        bad.append(f"{p}: switched off signal, so it cannot report back")
if bad:
    sys.exit("\n".join(bad))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "workers: every lane pin attaches its OWN switchboard endpoint, enabled" {
  _need
  # A lane that inherits the global switchboard entry drains the pool's queue
  # instead of its own, and a lane that switches switchboard off drains
  # nothing. Both look healthy in `harness list`.
  local w tmp="$BATS_TEST_TMPDIR" env queue
  for w in $(_lane_workers); do
    _render_pin "$w" >"$tmp/$w.json" || { echo "$w: pin failed to render"; return 1; }
    run python3 - "$tmp/$w.json" "$w" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); name = sys.argv[2]
sb = c.get("mcp", {}).get("switchboard")
if not sb:
    sys.exit(f"{name}: pin carries no switchboard entry, so it inherits the pool's endpoint")
if sb.get("disabled") is not False:
    sys.exit(f"{name}: switchboard is not explicitly enabled: {sb}")
url = sb.get("url", "")
if not url.startswith("$SWITCHBOARD_LANE") and not url.startswith("$SWITCHBOARD_TRIAGE"):
    sys.exit(f"{name}: switchboard url {url!r} is not a lane endpoint")
PY
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
}

@test "workers: every lane declares an mcp manifest, and only vision keeps a browser" {
  _need
  run chezmoi execute-template --source "$REPO_ROOT" \
    <<<'{{ range $l := .switchboard.lanes }}{{ $l.queue }}={{ join "," (default (list "MISSING") $l.mcp) }}
{{ end }}'
  [ "$status" -eq 0 ]
  local line queue keep
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    queue="${line%%=*}"; keep="${line#*=}"
    [ "$keep" != "MISSING" ] || { echo "$queue: no mcp manifest in .chezmoidata.yaml"; return 1; }
    case ",$keep," in *,switchboard,*) ;; *) echo "$queue: manifest drops switchboard"; return 1 ;; esac
    case ",$keep," in *,signal,*) ;; *) echo "$queue: manifest drops signal"; return 1 ;; esac
    if [ "$queue" = "lane-vision" ]; then
      case ",$keep," in *,chrome-devtools,*) ;; *) echo "$queue: the vision lane needs chrome-devtools"; return 1 ;; esac
    else
      case ",$keep," in
        *,chrome-devtools,*) echo "$queue: keeps chrome-devtools, which only lane-vision needs (5,933 tokens)"; return 1 ;;
      esac
    fi
  done <<<"$output"
}

@test "workers: no pin keeps a server the pool's history never called" {
  _need
  # aws, aws-knowledge, filesystem, memory and sequential-thinking were called
  # 3 times between them across ~1,500 recorded pool tool calls, and cost
  # 6,111 tokens per session. Keeping one again should be a deliberate edit
  # with a reason, not a quiet re-inheritance.
  local tmp="$BATS_TEST_TMPDIR" pin s
  for pin in $(_pin_dirs); do
    _render_pin "$pin" >"$tmp/$pin.json" || { echo "$pin: pin failed to render"; return 1; }
    for s in aws aws-knowledge filesystem memory sequential-thinking outline msgbrowse; do
      run python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if c.get("mcp",{}).get(sys.argv[2],{}).get("disabled") is True else 1)' "$tmp/$pin.json" "$s"
      [ "$status" -eq 0 ] || { echo "$pin: does not switch off $s"; return 1; }
    done
  done
}
