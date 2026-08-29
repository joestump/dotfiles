#!/usr/bin/env bats
# The scheduled harnesses: five one-shot prompt harnesses, one drop-in file
# each in dot_config/harness/harness.d/*.toml (stumpcloud-sweep every 6h,
# pr-sweep daily, issue-sweep + blog-sweep + navidrome-ldap-sync weekly), agent logins only,
# replacing the retired standalone stumpcloud-sweep systemd timer / launchd
# agent. These tests pin the couplings: every scheduled entry points at a
# prompt file that actually ships, the old units are gone from source AND
# listed in .chezmoiremove, and the reload script re-fires on config/prompt
# changes (daemon doesn't re-read config itself).
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/harness.toml.tmpl"
HARNESS_D="$REPO_ROOT/dot_config/harness/harness.d"
PROMPTS_DIR="$REPO_ROOT/dot_config/dotfiles"
RELOAD_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_52-harness-reload.sh.tmpl"
REMOVE="$REPO_ROOT/.chezmoiremove"
EXTERNALS="$REPO_ROOT/.chezmoiexternal.toml"
CRUSH_JSON="$REPO_ROOT/dot_config/crush/crush.json.tmpl"
PLUGINS_TSV="$REPO_ROOT/dot_config/dotfiles/claude-plugins.tsv.tmpl"

_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

# Render as an AGENT login regardless of who runs the suite — CI executes as
# root, and the scheduled block in harness.toml is gated on the `-agent`
# suffix. Without this the scheduled-harness tests silently test nothing on a
# human login and fail on CI's root.
# The host this suite is running on, as the template sees it. Needed because
# pr-sweep is host-gated (.sweeps.prSweepHost) and renders nothing unless the
# gate matches — see "pr-sweep is disarmed fleet-wide by default" below.
_this_host() {
  chezmoi execute-template --source "$REPO_ROOT" <<<'{{ .chezmoi.hostname }}'
}

_agent_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # mktemp --suffix is GNU-only; BSD/macOS mktemp rejects it. chezmoi infers
  # the config format from the extension, so mint the .toml inside a temp dir.
  # prSweepHost is armed to THIS host so the declaration-shape tests below
  # still see pr-sweep; the gate itself is tested separately.
  local cfgdir rc
  cfgdir="$(mktemp -d)"
  printf '[data]\n    agentIdentity = "ci-agent"\n[data.sweeps]\n    prSweepAgentHost = "%s"\n' "$(_this_host)" >"$cfgdir/chezmoi.toml"
  chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" < "$1"
  rc=$?
  rm -rf "$cfgdir"
  return $rc
}

# Render the full declared set — main config plus every harness.d drop-in —
# as an agent login, concatenated. The scheduled tables live only in the
# drop-ins, so tests asserting on them must render the whole set.
_agent_render_all() {
  local f
  _agent_render "$HARNESS_TOML" || return 1
  for f in "$HARNESS_D"/*.toml.tmpl; do
    _agent_render "$f" || return 1
  done
}

@test "scheduled: five scheduled harnesses declared with prompt + cron" {
  run _agent_render_all
  [ "$status" -eq 0 ]
  for name in stumpcloud-sweep pr-sweep issue-sweep blog-sweep navidrome-ldap-sync; do
    grep -qE "^\[harness\.$name\]" <<<"$output" || return 1
    # every scheduled entry needs `prompt` and a 5-field cron `schedule`
    grep -A8 "^\[harness\.$name\]" <<<"$output" | grep -q '^prompt = ' || return 1
    grep -A8 "^\[harness\.$name\]" <<<"$output" | grep -Eq '^schedule = "[0-9*/,]+ [0-9*/,]+ [0-9*/,-]+ [0-9A-Za-z*/,-]+ [0-7A-Za-z*/,-]*"' || return 1
    # schedule/profile membership is mutually exclusive — none may appear in a profile
    if sed -n '/^\[profile/,/^$/p' "$HARNESS_TOML" | grep -q "\"$name\""; then
      return 1
    fi
  done
}

# Z.ai's coding plan is subscription-metered with a hard weekly/monthly cap. When
# it ran out, every scheduled run died at stream-open and `restart = "on-failure"`
# relaunched them thousands of times -- 4417 on the StumpCloud sweep -- so no
# health sweep ran for four days and nothing said so. Hyper auto-tops-up, which
# turns that silent stall into a bigger bill. Guard the regression: a scheduled
# harness must never be pinned back to a hard-capped provider without a
# deliberate change here.
# Z.ai IS allowed again, deliberately, but only for sweeps that can survive a
# refusal. The August outage was never caused by the cap itself -- it was
# `restart = "on-failure"` turning each quota-exhausted stream-open into another
# relaunch (4417 on the StumpCloud sweep, 1795 on this one). With that amplifier
# gone, a hard cap is a FEATURE: Z.ai refuses and stops, where Hyper auto-tops-up
# and bills on. So the guard is no longer "never zai" -- it is "a zai pin must be
# accompanied by the restart policy that makes a refusal harmless".
@test "scheduled: any Z.ai-pinned sweep cannot relaunch itself into the cap" {
  run _agent_render_all
  [ "$status" -eq 0 ]
  local render_file
  render_file="$(mktemp)"
  printf '%s\n' "$output" >"$render_file"
  # NB: assert with a single command whose status stands. Bash's set -e never
  # fails on a `!`-negated command unless it is the last one in the test, so a
  # mid-test `! grep -q ...` is a silent no-op -- it passes whatever the render
  # says. (Several older assertions in this file are vacuous for that reason.)
  run python3 -c '
import re, sys
text = open(sys.argv[1]).read()
bad = []
for blk in re.split(r"^\[harness\.", text, flags=re.M)[1:]:
    name, _, body = blk.partition("]")
    body = re.split(r"^\[", body, flags=re.M)[0]
    scheduled = re.search(r"^schedule = ", body, re.M)
    zai       = re.search(r"^model = \"zai/", body, re.M)
    onfail    = re.search(r"^restart = \"on-failure\"", body, re.M)
    norestart = re.search(r"^restart = \"no\"", body, re.M)
    # An always-on harness may legitimately restart on failure; a SCHEDULED one
    # may not -- that is what turned quota exhaustion into 4417 relaunches.
    if scheduled and onfail:
        bad.append(name + ": scheduled harness declares restart=on-failure")
    if zai and not norestart:
        bad.append(name + ": zai-pinned harness lacks restart=\"no\"")
if bad:
    sys.exit("; ".join(bad))
' "$render_file"
  rm -f "$render_file"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# The other half of that outage. `restart = "on-failure"` is what turned each
# quota-exhausted stream-open into another relaunch, thousands of times over.
# harness has since made the policy unreachable for a scheduled harness --
# onProcessGone returns on `Schedule != ""` before consulting it (harness
# 1a3f286) -- so this assertion is belt-and-braces, not load-bearing. It is
# still worth pinning: the config must not go on declaring the policy that
# caused the outage, and if that early return is ever refactored away, `no` is
# what keeps a failing sweep from relaunching itself. A cron one-shot's
# schedule IS its retry.
@test "scheduled: no scheduled harness relaunches itself on failure" {
  run _agent_render_all
  [ "$status" -eq 0 ]
  ! grep -q '^restart = "on-failure"' <<<"$output"
  # Every scheduled harness states the policy explicitly rather than relying on
  # a default. Note the default would NOT catch a dropped line: `restart` is
  # only "always" when unset for an ordinary harness, and a scheduled one is
  # always a prompt harness (`schedule` requires `prompt`), which defaults to
  # "no" instead -- the same value, arrived at silently. So the explicit line
  # is the only thing that states the intent, and the only thing that still
  # holds if the prompt-harness default ever changes. Assert all five are
  # present and are "no".
  [ "$(grep -c '^restart = "no"' <<<"$output")" -eq 5 ]
}

@test "scheduled: cadences — sweep 6h, pr 3x/wk staggered, issue + blog + navidrome weekly" {
  run _agent_render_all
  grep -A8 '^\[harness\.stumpcloud-sweep\]' <<<"$output" | grep -q 'schedule = "0 \*/6 \* \* \*"'
  # 3x/week, and staggered against the human side's Tue/Thu/Sat so the two
  # identities alternate days instead of both firing daily.
  grep -A8 '^\[harness\.pr-sweep\]' <<<"$output" | grep -q 'schedule = "30 9 \* \* 1,3,5"'
  grep -A8 '^\[harness\.issue-sweep\]' <<<"$output" | grep -q 'schedule = "0 7 \* \* 1"'
  grep -A8 '^\[harness\.blog-sweep\]' <<<"$output" | grep -q 'schedule = "0 16 \* \* 5"'
  grep -A8 '^\[harness\.navidrome-ldap-sync\]' <<<"$output" | grep -q 'schedule = "0 6 \* \* 0"'
}

@test "scheduled: each scheduled prompt points at a prompt file that ships" {
  run _agent_render_all
  for f in stumpcloud-sweep pr-sweep issue-sweep blog-sweep navidrome-ldap-sync; do
    grep -q "$f.prompt.md" <<<"$output" || return 1
    # pr-feedback/grooming are templates (identity vars); the sweep prompt is
    # identity-free markdown. Either way the template must render cleanly.
    if [ -f "$PROMPTS_DIR/$f.prompt.md.tmpl" ]; then
      command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
      chezmoi execute-template --source "$REPO_ROOT" < "$PROMPTS_DIR/$f.prompt.md.tmpl" >/dev/null || return 1
    elif [ ! -f "$PROMPTS_DIR/$f.prompt.md" ]; then
      return 1
    fi
  done
}

@test "scheduled: pr-sweep prompt keeps the two-tier merge policy + Signal rule" {
  grep -qi 'SQUASH' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -q 'APPROVED' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -q 'chezmoi.username' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -q 'SIGNAL_MCP_OPERATOR' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
}

@test "scheduled: pr-sweep prompt pins the cross-identity approval rule" {
  # Neither identity may merge its own PR; the two identities unblock each
  # other - the sweep must APPROVE the opposite identity's eligible PRs and
  # never its own.
  grep -q 'reviews and approves PRs authored by' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -qi 'Never approve a PR authored by your OWN identity' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -qi 'auto-merge' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
}

@test "scheduled: pr-sweep prompt splits author mode from reviewer mode" {
  # The sweep wears exactly two hats, chosen by PR author: it responds to and
  # merges its OWN PRs, and it REVIEWS the sibling identity's. A PR authored by
  # anyone else is out of scope entirely - dropping that third row is how the
  # sweep starts reviewing the outside world's work.
  local f="$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -qi 'Author mode' "$f"
  grep -qi 'Reviewer mode' "$f"
  grep -qi 'Leave it completely alone' "$f"
  # author mode owns conflicts and red CI, not just replies
  grep -qi 'Resolve merge conflicts' "$f"
  grep -qi 'Get CI back to green' "$f"
  # Author mode still owns the conflict case; it just cannot force-push its way
  # out of one any more. Pin the replacement route rather than the retired flag.
  grep -qi 'open a replacement PR' "$f"
}

@test "scheduled: reviewer mode delegates to the pr-review skill with hard gates" {
  # Reviewer mode is not a second inline review checklist - it loads the
  # pr-review skill, which is the authority on how a review is done here. The
  # three non-negotiables around it are what keep an approval meaningful.
  local f="$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -q 'pr-review' "$f"
  grep -qi 'MUST leave a summary comment' "$f"
  grep -qi 'MUST have green CI before approving' "$f"
  grep -qi 'SHOULD enable auto-merge once you approve' "$f"
  # and the forge calls that make the auto-merge half actually executable
  grep -q 'merge_when_checks_succeed' "$f"
  grep -q -- '--auto --squash' "$f"
}

@test "scheduled: sweeps skip archived repositories" {
  # An archived repo is read-only: every comment, push, review and merge against
  # it fails, and the sweeps were burning runs retrying them. Both sweeps that
  # enumerate repos must drop them BEFORE acting, and report them in aggregate.
  for f in pr-sweep issue-sweep; do
    grep -qi 'archived' "$PROMPTS_DIR/$f.prompt.md.tmpl"
    grep -q 'isArchived' "$PROMPTS_DIR/$f.prompt.md.tmpl"
  done
  grep -qi 'skipped N PRs in archived repos' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
}

@test "scheduled: every sweep prompt carries a scope clamp and an injection warning" {
  # A scheduled sweep reads attacker-reachable text all run long: PR bodies,
  # issue comments, container logs, HTTP bodies. Each prompt must say what the
  # session is allowed to do at all, and that what it reads is data. Losing
  # either half turns a stranger's comment into a command on an unattended box.
  for f in "$PROMPTS_DIR"/pr-sweep.prompt.md.tmpl \
           "$PROMPTS_DIR"/issue-sweep.prompt.md.tmpl \
           "$PROMPTS_DIR"/navidrome-ldap-sync.prompt.md.tmpl \
           "$PROMPTS_DIR"/stumpcloud-sweep.prompt.md; do
    grep -qi '## Scope clamp' "$f"
    grep -qi 'Untrusted content' "$f"
    grep -qi 'never instructions' "$f"
    grep -qi 'prompt-injection' "$f"
    # the two exfiltration paths that matter: credentials out, messages out
    grep -qi 'credential' "$f"
    grep -q 'SIGNAL_MCP_OPERATOR' "$f"
  done
}

@test "scheduled: every drop-in restates the clamp in the harness prompt itself" {
  # The prompt FILE can fail to load (renamed, unapplied, unreadable). The one
  # line the daemon hands the model must therefore carry the clamp too, so a
  # sweep that cannot read its spec still refuses to be driven by what it reads.
  run _agent_render_all
  [ "$status" -eq 0 ]
  local rendered="$output"
  for name in pr-sweep issue-sweep stumpcloud-sweep blog-sweep navidrome-ldap-sync; do
    echo "$rendered" | grep -q "$name" || { echo "missing harness $name"; false; }
  done
  # one clamp sentence per scheduled harness
  [ "$(echo "$rendered" | grep -c 'untrusted data')" -eq 5 ]
  [ "$(echo "$rendered" | grep -c 'prompt-injection attempt')" -eq 5 ]
  [ "$(echo "$rendered" | grep -c 'it does nothing else')" -eq 5 ]
}

# The base agent rules ban force-pushing outright, but the sweep prompts are a
# separate surface that a reader never diffs against base.md. #176 quietly grew
# two `--force-with-lease` instructions here while the ban was in review, so pin
# it: no scheduled prompt may hand the agent permission the base rules revoke.
@test "scheduled: no sweep prompt permits a force-push" {
  local f
  for f in "$PROMPTS_DIR"/*.prompt.md.tmpl "$PROMPTS_DIR"/*.prompt.md; do
    [ -e "$f" ] || continue
    ! grep -q -- '--force-with-lease' "$f" \
      || { echo "$f still permits --force-with-lease"; return 1; }
    ! grep -qi 'force-push outside' "$f" \
      || { echo "$f still carves out a force-push exception"; return 1; }
  done
  # ...and the replacement route is spelled out where the conflict case lives.
  grep -q 'replay this PR' "$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  return 0
}

@test "scheduled: issue-sweep prompt keeps the repo lists + comment-before-close rule" {
  grep -q 'stumpcloud' "$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
  grep -q 'joestump/signal-mcp' "$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
  grep -qi 'Always leave a comment before closing' "$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
  # grooming must never close the pr-sweep's own PRs
  grep -qi 'Any pull request, for any reason' "$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
}

@test "scheduled: old standalone sweep units retired everywhere" {
  # gone from source
  [ ! -e "$REPO_ROOT/dot_config/systemd/user/stumpcloud-sweep.service.tmpl" ]
  [ ! -e "$REPO_ROOT/dot_config/systemd/user/stumpcloud-sweep.timer.tmpl" ]
  [ ! -e "$REPO_ROOT/Library/LaunchAgents/rocks.stump.stumpcloud-sweep.plist.tmpl" ]
  # removed from machines that already applied them
  grep -qx '.config/systemd/user/stumpcloud-sweep.service' "$REMOVE"
  grep -qx '.config/systemd/user/stumpcloud-sweep.timer' "$REMOVE"
  grep -qx 'Library/LaunchAgents/rocks.stump.stumpcloud-sweep.plist' "$REMOVE"
  # and the reload script tears the running units down
  grep -q 'stumpcloud-sweep.timer' "$RELOAD_SCRIPT"
}

@test "scheduled: reload script re-fires when harness.toml or a prompt changes" {
  # the daemon does not re-read config (stump.wtf/harness#98); run_onchange_
  # only re-fires when the rendered script text changes, so the hashes of
  # everything the schedule depends on must be embedded in it.
  for f in dot_config/harness/harness.toml.tmpl \
           dot_config/harness/harness.d/stumpcloud-sweep.toml.tmpl \
           dot_config/harness/harness.d/pr-sweep.toml.tmpl \
           dot_config/harness/harness.d/issue-sweep.toml.tmpl \
           dot_config/dotfiles/stumpcloud-sweep.prompt.md \
           dot_config/dotfiles/pr-sweep.prompt.md.tmpl \
           dot_config/dotfiles/issue-sweep.prompt.md.tmpl; do
    grep -q "$f" "$RELOAD_SCRIPT" || return 1
  done
  grep -q 'harness reload\|HARNESS_BIN" reload' "$RELOAD_SCRIPT" || return 1
}

@test "scheduled: human logins get pr-sweep and nothing else" {
  # pr-sweep is the ONE sweep that runs under both identities - that is what
  # keeps Joe reviewing the agent's PRs on a schedule instead of by hand. The
  # other two stay agent-only. Both gates have to agree: .chezmoiignore must
  # ship the prompt, and the drop-in must declare the table.
  grep -q 'issue-sweep.prompt.md' "$REPO_ROOT/.chezmoiignore"
  grep -q 'stumpcloud-sweep.prompt.md' "$REPO_ROOT/.chezmoiignore"
  ! grep -q 'pr-sweep.prompt.md' "$REPO_ROOT/.chezmoiignore"

  # agent-only drop-ins keep the suffix gate; pr-sweep must NOT have one --
  # it runs under both identities. What it has instead is a HOST gate, so it
  # runs on one machine rather than on every machine that renders it.
  grep -q 'hasSuffix "-agent"' "$HARNESS_D/issue-sweep.toml.tmpl"
  grep -q 'hasSuffix "-agent"' "$HARNESS_D/stumpcloud-sweep.toml.tmpl"
  ! grep -q '{{ if hasSuffix "-agent"' "$HARNESS_D/pr-sweep.toml.tmpl"
  grep -q 'sweeps.prSweepAgentHost' "$HARNESS_D/pr-sweep.toml.tmpl"
}

@test "scheduled: a human login renders pr-sweep only, on its own cadence" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir out
  cfgdir="$(mktemp -d)"
  printf '[data]\n    agentIdentity = "ci-human"\n[data.sweeps]\n    prSweepHumanHost = "%s"\n' "$(_this_host)" >"$cfgdir/chezmoi.toml"
  out=""
  for f in "$HARNESS_D"/*.toml.tmpl; do
    out+="$(chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" < "$f")"
  done
  rm -rf "$cfgdir"
  # the one sweep a human runs, staggered off the agent's 09:30
  grep -q '^\[harness\.pr-sweep\]' <<<"$out"
  grep -A8 '^\[harness\.pr-sweep\]' <<<"$out" | grep -q 'schedule = "30 15 \* \* 2,4,6"'
  # and none of the agent-only ones
  ! grep -q '^\[harness\.issue-sweep\]' <<<"$out"
  ! grep -q '^\[harness\.stumpcloud-sweep\]' <<<"$out"
}

@test "scheduled: the two sweeps are disjoint — issues here, PRs there" {
  # They used to overlap: issue-pr-grooming closed PRs as well as issues, kept
  # off pr-feedback-sweep's toes only by a "not the acting identity's own PRs"
  # carve-out. Now each owns one object type outright.
  local iss="$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
  local prs="$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  grep -qi 'You own issues. You do not touch pull requests' "$iss"
  grep -qi 'You own pull requests. You do not touch issues' "$prs"
  # the issue sweep must no longer carry PR-closing rules
  ! grep -qi '^### PRs — close if ANY apply' "$iss"
  # and the PR sweep owns closing them instead
  grep -qi 'close stale and superseded PRs' "$prs"
}

@test "scheduled: issue sweep triages on evidence and sizes, not on age" {
  # The old rules closed anything untouched for 90 days. Age is now explicitly
  # not a closing reason, a merged PR's closing keyword is not evidence, and
  # every surviving issue gets exactly one size/* label.
  local f="$PROMPTS_DIR/issue-sweep.prompt.md.tmpl"
  grep -qi 'Age is not evidence' "$f"
  grep -qi 'is \*\*not\*\* evidence' "$f"
  ! grep -qi 'Stale with no activity for 90+ days' "$f"
  for l in 'size/S' 'size/M' 'size/L' 'size/XL'; do
    grep -q "$l" "$f" || return 1
  done
  grep -qi 'exactly one' "$f"
  # and the retired competing scale must not come back
  grep -qi 'sonnet-ready' "$f"
}

@test "scheduled: every sweep is pinned per entry, to its own cheap model" {
  # Unattended permission-free runs — the model is pinned per entry (harness
  # appends --model), so a config-wide model change can never silently retarget
  # them.
  #
  # stumpcloud-sweep and the two weekly passes moved off hyper/glm-5.2 on
  # 2026-08-28 in the Hyper cost review: prism is the router (it picks per
  # prompt, so an idle health check and a real PR review do not pay the same
  # rate), and qwen3.8-flash is the cheap fixed pin for a bounded weekly pass.
  #
  # pr-sweep moved AGAIN on 2026-08-29, to zai/glm-5.3-flash: after it burned
  # ~$80 in an hour, a subscription plan whose session limit refuses at
  # stream-open beats a metered one that auto-tops-up. Different provider, so
  # it is asserted separately rather than folded into the hyper/ loop.
  run _agent_render_all
  for pin in stumpcloud-sweep:prism issue-sweep:qwen3.8-flash blog-sweep:qwen3.8-flash; do
    name=${pin%%:*}
    model=${pin##*:}
    grep -A10 "^\[harness\.$name\]" <<<"$output" | grep -q "model = \"hyper/$model\"" || return 1
  done
  grep -A12 '^\[harness\.pr-sweep\]' <<<"$output" | grep -q 'model = "zai/glm-5.3-flash"' || return 1
}

@test "scheduled: no sweep runs on a premium-tier model" {
  # The sweeps are unattended and metered per token, so an expensive pin is a
  # bill nobody is watching accrue. kimi-k3 in particular is what the crush-signal
  # pin silently drifted to ($3.27/M in, $16.33/M out); it must never reach a
  # cron one-shot. glm-5.2 is listed because these three were on it until the
  # cost review, and a careless revert is the likely way it comes back.
  run _agent_render_all
  for model in kimi-k3 kimi-k2.7-code glm-5.2 glm-5.1 deepseek-v4-pro qwen3.7-max qwen3.6-max qwen3.8-max; do
    ! grep -q "model = \"hyper/$model\"" <<<"$output" || return 1
  done
}

@test "scheduled: blog-sweep opens a PR and never merges" {
  # blog-sweep is the only sweep whose output is PUBLIC and irreversible —
  # apps.stump.wtf has no draft mode, so merged is live and CloudFront-cached.
  # The blog-post skill's own workflow ends in merge-and-verify; the scheduled
  # run deliberately stops at the PR so a human approves public writing. That
  # override lives in two places and both must hold: the prompt FILE, and the
  # one-line clamp the daemon hands the model in case the file cannot be read.
  local f="$PROMPTS_DIR/blog-sweep.prompt.md.tmpl"
  grep -qi 'You open a PR. You never merge' "$f"
  grep -qi 'do not merge' "$f"
  grep -qi 'auto-merge' "$f"

  run _agent_render_all
  [ "$status" -eq 0 ]
  local clamp
  clamp=$(grep -A3 '^\[harness\.blog-sweep\]' <<<"$output" | grep '^prompt =')
  grep -q 'NEVER merges' <<<"$clamp"
  grep -q 'never pushes to main' <<<"$clamp"
  grep -q 'never enables auto-merge' <<<"$clamp"
}

@test "scheduled: blog-sweep may produce nothing, and says so" {
  # A weekly cron that MUST emit a post emits filler, and filler is permanently
  # public. The prompt has to authorize the empty run explicitly, or a model
  # trying to be useful will invent a story out of dependency bumps.
  local f="$PROMPTS_DIR/blog-sweep.prompt.md.tmpl"
  grep -qi 'no post' "$f"
  grep -qi 'successful run' "$f"
  grep -qi 'filler' "$f"
}

@test "scheduled: blog-sweep never writes about StumpCloud" {
  # Infra is not studio content; a public post about it is a disclosure. The
  # skill says so, but nobody is watching this run, so the clamp is restated in
  # both the prompt file and the daemon's one-liner.
  grep -qi 'never stumpcloud' "$PROMPTS_DIR/blog-sweep.prompt.md.tmpl"
  run _agent_render_all
  grep -A3 '^\[harness\.blog-sweep\]' <<<"$output" | grep -q 'never writes about the stumpcloud org'
}

@test "scheduled: prompts carry the Harness attribution footer, no PII" {
  for f in pr-sweep issue-sweep; do
    grep -qF 'Executed via scheduled [Harness]' "$PROMPTS_DIR/$f.prompt.md.tmpl"
    grep -q 'openrouter.ai' "$PROMPTS_DIR/$f.prompt.md.tmpl"
    # No phone numbers in the repo (identity values resolve from env at runtime)
    ! grep -qE '\+1[0-9]{9,}' "$PROMPTS_DIR/$f.prompt.md.tmpl"
  done
  ! grep -qE '\+1[0-9]{9,}' "$PROMPTS_DIR/stumpcloud-sweep.prompt.md"
}

# The footer lands on PUBLIC GitHub PRs and issues, where a gitea.stump.rocks
# link is unopenable. Assert on the RENDERED prompt so a stale .chezmoidata
# value or a hardcoded Gitea URL both fail here.
@test "scheduled: the Harness attribution link is the public GitHub mirror, never Gitea" {
  for f in pr-sweep issue-sweep; do
    local out
    out="$(chezmoi execute-template --source "$REPO_ROOT" < "$PROMPTS_DIR/$f.prompt.md.tmpl")"
    grep -qF '[Harness](https://github.com/stump-wtf/harness)' <<< "$out"
    ! grep -q 'gitea\.stump\.rocks/stump\.wtf/harness' <<< "$out"
  done
}

# The drop-ins are where a future editor adds the next scheduled sweep, so the
# rule has to be visible there too, not only in the prompt files.
@test "scheduled: drop-ins record the public-link rule for the attribution footer" {
  for f in pr-sweep issue-sweep stumpcloud-sweep; do
    grep -q 'ATTRIBUTION LINKS ARE PUBLIC' "$REPO_ROOT/dot_config/harness/harness.d/$f.toml.tmpl"
  done
}

@test "harness-config skill: loads in Crush (external + skills path)" {
  grep -q 'claude-plugin-harness' "$EXTERNALS"
  grep -q 'gitea.stump.rocks/stump.wtf/claude-plugin-harness' "$EXTERNALS"
  _render "$CRUSH_JSON" | grep -q 'skills-ext/claude-plugin-harness/skills'
}

@test "harness-config skill: loads in Claude Code (plugins tsv)" {
  grep -q 'claude-plugin-harness.git' "$PLUGINS_TSV"
  grep -q 'harness@claude-plugin-harness' "$PLUGINS_TSV"
}

# A drop-in cron is evaluated in each host's LOCAL time, so an ungated
# `30 15 * * *` on three machines in two timezones is three independent full
# runs a day, not one. pr-sweep lost its `-agent` gate on 2026-08-25 (so the
# human identity would sweep too) and nothing replaced it, so every
# human-identity machine armed its own. On 2026-08-29 that billed ~$80 of
# Hyper in under an hour, invisibly. These three tests pin the gate.
@test "scheduled: pr-sweep never arms on a machine that owns neither identity" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir
  cfgdir="$(mktemp -d)"
  # The MacBook case: a real host that is neither the agent host nor the human
  # host. It must render NO harness table, under EITHER identity — an
  # interactive machine runs no scheduled sweep.
  for ident in ci-agent ci-human; do
    printf '[data]\n    agentIdentity = "%s"\n[data.sweeps]\n    prSweepAgentHost = "some-agent-box"\n    prSweepHumanHost = "some-human-box"\n' \
      "$ident" >"$cfgdir/chezmoi.toml"
    run chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" \
      < "$HARNESS_D/pr-sweep.toml.tmpl"
    [ "$status" -eq 0 ]
    ! grep -q '^\[harness\.pr-sweep\]' <<<"$output"
    ! grep -q '^schedule = ' <<<"$output"
  done
  # An empty host disarms that identity entirely.
  printf '[data]\n    agentIdentity = "ci-human"\n[data.sweeps]\n    prSweepHumanHost = ""\n' >"$cfgdir/chezmoi.toml"
  run chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" \
    < "$HARNESS_D/pr-sweep.toml.tmpl"
  [ "$status" -eq 0 ]
  ! grep -q '^\[harness\.pr-sweep\]' <<<"$output"
  rm -rf "$cfgdir"
}

@test "scheduled: the shipped defaults pin agent->tars, human->kitt, Mac->nothing" {
  grep -qE '^  prSweepAgentHost: "tars"' "$REPO_ROOT/.chezmoidata.yaml"
  grep -qE '^  prSweepHumanHost: "kitt"' "$REPO_ROOT/.chezmoidata.yaml"
  # neither key may name a laptop
  ! grep -qE '^  prSweep(Agent|Human)Host: "macbook' "$REPO_ROOT/.chezmoidata.yaml"
}

@test "scheduled: pr-sweep arms for each identity on its own designated host" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local cfgdir
  cfgdir="$(mktemp -d)"

  # matching host -> renders, with the identity-staggered cadence intact
  printf '[data]\n    agentIdentity = "ci-human"\n[data.sweeps]\n    prSweepHumanHost = "%s"\n' \
    "$(_this_host)" >"$cfgdir/chezmoi.toml"
  run chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" \
    < "$HARNESS_D/pr-sweep.toml.tmpl"
  [ "$status" -eq 0 ]
  grep -q '^\[harness\.pr-sweep\]' <<<"$output"
  grep -q 'schedule = "30 15 \* \* 2,4,6"' <<<"$output"

  # the agent identity on the HUMAN's host -> nothing: the gate is per identity
  printf '[data]\n    agentIdentity = "ci-agent"\n[data.sweeps]\n    prSweepHumanHost = "%s"\n    prSweepAgentHost = "some-other-box"\n' \
    "$(_this_host)" >"$cfgdir/chezmoi.toml"
  run chezmoi execute-template --config "$cfgdir/chezmoi.toml" --source "$REPO_ROOT" \
    < "$HARNESS_D/pr-sweep.toml.tmpl"
  [ "$status" -eq 0 ]
  ! grep -q '^\[harness\.pr-sweep\]' <<<"$output"

  rm -rf "$cfgdir"
}

@test "scheduled: pr-sweep prompt carries a hard run budget and reports its cost" {
  local p="$PROMPTS_DIR/pr-sweep.prompt.md.tmpl"
  # An unbudgeted run chose, on its own, to do full diff reviews plus local
  # test verification on 13 third-party PRs. Every ceiling below is load-bearing.
  grep -q '## Run budget' "$p"
  grep -q 'At most 6 PRs total' "$p"
  grep -q 'Repos we own, and nothing else' "$p"
  grep -q '30 minutes' "$p"
  # Z.ai is subscription-metered, so any per-token figure is not a charge --
  # the summary must say so, and must surface a quota refusal, which is the
  # only cost signal that exists on this plan.
  grep -q 'run cost' "$p"
  grep -q 'subscription-metered' "$p"
  grep -qi 'quota' "$p"
}
