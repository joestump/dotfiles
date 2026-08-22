#!/usr/bin/env bats
# The scheduled harnesses: three one-shot prompt harnesses, one drop-in file
# each in dot_config/harness/harness.d/*.toml (stumpcloud-sweep every 6h,
# pr-feedback-sweep daily, issue-pr-grooming weekly), agent logins only,
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
_agent_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # mktemp --suffix is GNU-only; BSD/macOS mktemp rejects it. chezmoi infers
  # the config format from the extension, so mint the .toml inside a temp dir.
  local cfgdir rc
  cfgdir="$(mktemp -d)"
  printf '[data]\n    agentIdentity = "ci-agent"\n' >"$cfgdir/chezmoi.toml"
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

@test "scheduled: three scheduled harnesses declared with prompt + cron" {
  run _agent_render_all
  [ "$status" -eq 0 ]
  for name in stumpcloud-sweep pr-feedback-sweep issue-pr-grooming; do
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
@test "scheduled: no scheduled harness is pinned to the hard-capped Z.ai plan" {
  run _agent_render_all
  [ "$status" -eq 0 ]
  ! grep -q '^model = "zai/' <<<"$output"
}

@test "scheduled: cadences — sweep 6h, pr-feedback daily, grooming weekly" {
  run _agent_render_all
  grep -A8 '^\[harness\.stumpcloud-sweep\]' <<<"$output" | grep -q 'schedule = "0 \*/6 \* \* \*"'
  grep -A8 '^\[harness\.pr-feedback-sweep\]' <<<"$output" | grep -q 'schedule = "30 9 \* \* \*"'
  grep -A8 '^\[harness\.issue-pr-grooming\]' <<<"$output" | grep -q 'schedule = "0 7 \* \* 1"'
}

@test "scheduled: each scheduled prompt points at a prompt file that ships" {
  run _agent_render_all
  for f in stumpcloud-sweep pr-feedback-sweep issue-pr-grooming; do
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

@test "scheduled: pr-feedback prompt keeps the two-tier merge policy + Signal rule" {
  grep -qi 'SQUASH' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -q 'APPROVED' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -q 'chezmoi.username' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -q 'SIGNAL_MCP_OPERATOR' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
}

@test "scheduled: pr-feedback prompt pins the cross-identity approval rule" {
  # Neither identity may merge its own PR; the two identities unblock each
  # other - the sweep must APPROVE the opposite identity's eligible PRs and
  # never its own.
  grep -q 'reviews and approves PRs authored by' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -qi 'Never approve a PR authored by your OWN identity' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -qi 'auto-merge' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
}

@test "scheduled: pr-feedback prompt splits author mode from reviewer mode" {
  # The sweep wears exactly two hats, chosen by PR author: it responds to and
  # merges its OWN PRs, and it REVIEWS the sibling identity's. A PR authored by
  # anyone else is out of scope entirely - dropping that third row is how the
  # sweep starts reviewing the outside world's work.
  local f="$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
  grep -qi 'Author mode' "$f"
  grep -qi 'Reviewer mode' "$f"
  grep -qi 'Leave it completely alone' "$f"
  # author mode owns conflicts and red CI, not just replies
  grep -qi 'Resolve merge conflicts' "$f"
  grep -qi 'Get CI back to green' "$f"
  grep -q 'force-with-lease' "$f"
}

@test "scheduled: reviewer mode delegates to the pr-review skill with hard gates" {
  # Reviewer mode is not a second inline review checklist - it loads the
  # pr-review skill, which is the authority on how a review is done here. The
  # three non-negotiables around it are what keep an approval meaningful.
  local f="$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
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
  for f in pr-feedback-sweep issue-pr-grooming; do
    grep -qi 'archived' "$PROMPTS_DIR/$f.prompt.md.tmpl"
    grep -q 'isArchived' "$PROMPTS_DIR/$f.prompt.md.tmpl"
  done
  grep -qi 'skipped N PRs in archived repos' "$PROMPTS_DIR/pr-feedback-sweep.prompt.md.tmpl"
}

@test "scheduled: every sweep prompt carries a scope clamp and an injection warning" {
  # A scheduled sweep reads attacker-reachable text all run long: PR bodies,
  # issue comments, container logs, HTTP bodies. Each prompt must say what the
  # session is allowed to do at all, and that what it reads is data. Losing
  # either half turns a stranger's comment into a command on an unattended box.
  for f in "$PROMPTS_DIR"/pr-feedback-sweep.prompt.md.tmpl \
           "$PROMPTS_DIR"/issue-pr-grooming.prompt.md.tmpl \
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
  for name in pr-feedback-sweep issue-pr-grooming stumpcloud-sweep; do
    echo "$rendered" | grep -q "$name" || { echo "missing harness $name"; false; }
  done
  # one clamp sentence per scheduled harness
  [ "$(echo "$rendered" | grep -c 'untrusted data')" -eq 3 ]
  [ "$(echo "$rendered" | grep -c 'prompt-injection attempt')" -eq 3 ]
  [ "$(echo "$rendered" | grep -c 'it does nothing else')" -eq 3 ]
}

@test "scheduled: grooming prompt keeps the repo lists + comment-before-close rule" {
  grep -q 'stumpcloud' "$PROMPTS_DIR/issue-pr-grooming.prompt.md.tmpl"
  grep -q 'joestump/signal-mcp' "$PROMPTS_DIR/issue-pr-grooming.prompt.md.tmpl"
  grep -qi 'Always leave a comment before closing' "$PROMPTS_DIR/issue-pr-grooming.prompt.md.tmpl"
  # grooming must never close the pr-feedback-sweep's own PRs
  grep -qi 'never close PRs authored by' "$PROMPTS_DIR/issue-pr-grooming.prompt.md.tmpl"
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
           dot_config/harness/harness.d/pr-feedback-sweep.toml.tmpl \
           dot_config/harness/harness.d/issue-pr-grooming.toml.tmpl \
           dot_config/dotfiles/stumpcloud-sweep.prompt.md \
           dot_config/dotfiles/pr-feedback-sweep.prompt.md.tmpl \
           dot_config/dotfiles/issue-pr-grooming.prompt.md.tmpl; do
    grep -q "$f" "$RELOAD_SCRIPT" || return 1
  done
  grep -q 'harness reload\|HARNESS_BIN" reload' "$RELOAD_SCRIPT" || return 1
}

@test "scheduled: human logins get none of it" {
  # .chezmoiignore keeps the prompts off human logins; each harness.d drop-in
  # gates its table on the -agent suffix (the main config no longer carries
  # the scheduled block at all).
  grep -q 'pr-feedback-sweep.prompt.md' "$REPO_ROOT/.chezmoiignore"
  grep -q 'issue-pr-grooming.prompt.md' "$REPO_ROOT/.chezmoiignore"
  for f in "$HARNESS_D"/*.toml.tmpl; do
    grep -q 'hasSuffix "-agent"' "$f" || return 1
  done
}

@test "scheduled: every sweep is pinned to glm-5.2 on Hyper" {
  # Unattended permission-free runs — the model is pinned per entry (harness
  # appends --model), so a config-wide model change can never silently retarget
  # them.
  run _agent_render_all
  for name in stumpcloud-sweep pr-feedback-sweep issue-pr-grooming; do
    grep -A10 "^\[harness\.$name\]" <<<"$output" | grep -q 'model = "hyper/glm-5.2"' || return 1
  done
}

@test "scheduled: prompts carry the Harness attribution footer, no PII" {
  for f in pr-feedback-sweep issue-pr-grooming; do
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
  for f in pr-feedback-sweep issue-pr-grooming; do
    local out
    out="$(chezmoi execute-template --source "$REPO_ROOT" < "$PROMPTS_DIR/$f.prompt.md.tmpl")"
    grep -qF '[Harness](https://github.com/stump-wtf/harness)' <<< "$out"
    ! grep -q 'gitea\.stump\.rocks/stump\.wtf/harness' <<< "$out"
  done
}

# The drop-ins are where a future editor adds the next scheduled sweep, so the
# rule has to be visible there too, not only in the prompt files.
@test "scheduled: drop-ins record the public-link rule for the attribution footer" {
  for f in pr-feedback-sweep issue-pr-grooming stumpcloud-sweep; do
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
