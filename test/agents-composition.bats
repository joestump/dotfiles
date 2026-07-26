#!/usr/bin/env bats
# The agent-rules hierarchy: one base policy (.chezmoitemplates/agents/base.md)
# plus an identity overlay plus a per-harness overlay, composed by chezmoi into
# ~/.claude/CLAUDE.md, ~/.config/crush/CRUSH.md and ~/.config/agents/AGENTS.md.
#
# What these guard: the failure mode that motivated the refactor is a rule getting
# added to ONE harness's file and silently not applying to the others. So the
# central assertion is that shared policy renders identically into every target.
load test_helper

setup() {
  command -v chezmoi >/dev/null || skip "chezmoi not installed"
  CLAUDE_OUT="$(chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_claude/CLAUDE.md.tmpl")"
  CRUSH_OUT="$(chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_config/crush/CRUSH.md.tmpl")"
  AGENTS_OUT="$(chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_config/agents/AGENTS.md.tmpl")"
}

# ────── every target actually renders something ──────

@test "all three agent targets render non-empty" {
  [ "${#CLAUDE_OUT}" -gt 2000 ]
  [ "${#CRUSH_OUT}" -gt 2000 ]
  [ "${#AGENTS_OUT}" -gt 2000 ]
}

# An empty-but-valid render is the classic chezmoi failure (see czu-run-env.bats):
# a template that gates on env vars renders blank under launchd. These files must
# never depend on the environment, so a bare-env render must be byte-identical.
@test "renders identically with an empty environment" {
  local bare
  bare="$(env -i PATH="$PATH" HOME="$HOME" chezmoi execute-template --source "$REPO_ROOT" < "$REPO_ROOT/dot_claude/CLAUDE.md.tmpl")"
  [ "$bare" = "$CLAUDE_OUT" ]
}

# ────── shared policy reaches every harness ──────

@test "shared policy sections appear in all three targets" {
  local section
  for section in \
    "## OMGs" \
    "## Issue tracking" \
    "## Git workflow" \
    "## Switchboard" \
    "## Signal Message Formatting" \
    "## URLs" \
    "## Outline Daily Log" \
    "## Creating and configuring repositories" \
    "## Workflow (CI/CD) expectations" \
    "## Cairn" \
    "## Code quality" \
    "## Communication"
  do
    echo "$CLAUDE_OUT" | grep -qF "$section" || { echo "missing from CLAUDE.md: $section"; return 1; }
    echo "$CRUSH_OUT"  | grep -qF "$section" || { echo "missing from CRUSH.md: $section";  return 1; }
    echo "$AGENTS_OUT" | grep -qF "$section" || { echo "missing from AGENTS.md: $section"; return 1; }
  done
}

# The whole point of the refactor: base policy is byte-identical everywhere, so a
# rule cannot apply to one harness and not another.
@test "the shared base renders byte-identically into every target" {
  local base
  base="$(chezmoi execute-template --source "$REPO_ROOT" <<< '{{ template "agents/base.md" . }}')"
  [ -n "$base" ]
  case "$CLAUDE_OUT" in *"$base"*) ;; *) echo "CLAUDE.md base diverged"; return 1;; esac
  case "$CRUSH_OUT"  in *"$base"*) ;; *) echo "CRUSH.md base diverged";  return 1;; esac
  case "$AGENTS_OUT" in *"$base"*) ;; *) echo "AGENTS.md base diverged"; return 1;; esac
}

# ────── harness overlays stay in their lane ──────

@test "each harness target gets its own overlay and not the other's" {
  echo "$CLAUDE_OUT" | grep -qF "## Claude Code specifics"
  echo "$CLAUDE_OUT" | grep -qvF "## Crush specifics"
  echo "$CRUSH_OUT"  | grep -qF "## Crush specifics"
  run grep -cF "## Claude Code specifics" <<< "$CRUSH_OUT"
  [ "$output" -eq 0 ]
}

# AGENTS.md is the harness-agnostic artifact — by definition no overlay at all.
@test "AGENTS.md carries no harness overlay" {
  run grep -cE '^## (Claude Code|Crush) specifics' <<< "$AGENTS_OUT"
  [ "$output" -eq 0 ]
}

# Scheduled tasks are a Claude-Code-only capability (no scheduled-tasks MCP in
# Crush), so that rule must NOT leak into the Crush rules.
@test "scheduled-task rules stay in the Claude Code overlay" {
  echo "$CLAUDE_OUT" | grep -qF "scheduled-tasks MCP"
  run grep -cF "Every scheduled task must send" <<< "$CRUSH_OUT"
  [ "$output" -eq 0 ]
}

# ────── identity axis ──────

@test "the default identity is joestump and carries the attribution footer" {
  grep -q '^agentIdentity: "joestump"$' "$REPO_ROOT/.chezmoidata.yaml"
  echo "$CLAUDE_OUT" | grep -qF "Posted on behalf of"
  echo "$CRUSH_OUT"  | grep -qF "Posted on behalf of"
}

@test "both identity overlays exist so the printf lookup can never miss" {
  [ -f "$REPO_ROOT/.chezmoitemplates/agents/identity-joestump.md" ]
  [ -f "$REPO_ROOT/.chezmoitemplates/agents/identity-joestump-agent.md" ]
}

# The agent signs as itself; using Joe's footer would misattribute the work.
@test "the joestump-agent identity drops the on-behalf-of footer" {
  local agent_id
  agent_id="$(cat "$REPO_ROOT/.chezmoitemplates/agents/identity-joestump-agent.md")"
  grep -qF "must **not** carry the" <<< "$agent_id"
  run grep -cE '^🤖 Posted on behalf of' <<< "$agent_id"
  [ "$output" -eq 0 ]
}

# ────── the anti-drift rule ──────

# Overlays are for capability deltas only. A fat overlay means policy leaked in,
# which is exactly how the old CLAUDE.md/CRUSH.md pair drifted apart.
@test "harness overlays stay thin (policy belongs in base.md)" {
  local f n
  for f in "$REPO_ROOT"/.chezmoitemplates/agents/harness-*.md; do
    n=$(wc -l < "$f")
    [ "$n" -le 30 ] || { echo "$(basename "$f") is $n lines — move policy to base.md"; return 1; }
  done
}

# ────── git workflow ──────

# Codified after stump.wtf/msgbrowse#245: 26 commits, 2 merge commits, 1 semantic
# prefix, and 24 issue refs carried over from an archived fork. Each rule below
# exists because that PR broke it.
@test "git workflow covers every failure mode from msgbrowse#245" {
  local rule
  for rule in \
    "Rebase. Never merge" \
    "force-with-lease" \
    "One PR = one concern" \
    "Semantic prefix, always" \
    "must belong to the repo you are committing into" \
    "Never bundle a migration with feature work" \
    "One branch = one concern" \
    "Never reuse a merged branch"
  do
    echo "$CLAUDE_OUT" | grep -qF "$rule" || { echo "missing git rule: $rule"; return 1; }
  done
}

# Host-agnostic by design: the rules must not assume gh/GitHub, since half of
# Joe's forges are Gitea.
@test "git workflow is stated host-agnostically" {
  echo "$CLAUDE_OUT" | grep -qF "host-, OS- and harness-agnostic"
  # Spell out what Gitea is authoritative FOR, not just that it is.
  echo "$CLAUDE_OUT" | grep -qF "Origin of truth for their git history, issues, PRs and CI"
  echo "$CLAUDE_OUT" | grep -qF "never push here"
  echo "$CLAUDE_OUT" | grep -qF "read-only downstream mirror"
}

@test "worktree guidance is concrete and portable" {
  echo "$CLAUDE_OUT" | grep -qF "git worktree add"
  echo "$CLAUDE_OUT" | grep -qF "git worktree remove"
  # The binding rule is invisibility to git, not physical location — see
  # "worktree rule defers to the harness convention" below.
  echo "$CLAUDE_OUT" | grep -qF "must never be visible to git"
}

@test "stump.wtf is the repo-creation default and is mirrored, not pushed" {
  echo "$CLAUDE_OUT" | grep -qF "stump.wtf"
  echo "$CLAUDE_OUT" | grep -qF "push_mirrors"
}

# ────── repo creation + CI/CD expectations (PR #96 review) ──────

@test "repo creation covers org, agent collaborator, metadata, protection and CI" {
  local rule
  for rule in \
    "Default to the \`stump.wtf\` org" \
    "push_mirrors" \
    "joestump-agent" \
    "Topics / labels" \
    "Website URL" \
    "Gitea Pages" \
    "branch protection on \`main\`" \
    "must be marked required" \
    "make test" \
    "gitleaks"
  do
    echo "$CLAUDE_OUT" | grep -qF "$rule" || { echo "missing repo-setup rule: $rule"; return 1; }
  done
}

# Gitea runs the real CI (it is the authoritative remote); GitHub Actions is only
# for publishing public artifacts, so the matrix must not be duplicated there.
@test "workflow expectations distinguish Gitea CI from GitHub publishing" {
  echo "$CLAUDE_OUT" | grep -qF "Gitea Actions is the real CI"
  echo "$CLAUDE_OUT" | grep -qF "only for publishing public artifacts"
}

@test "every repo must expose make test / make lint" {
  echo "$CLAUDE_OUT" | grep -qF 'Always run `make test lint` before pushing'
  echo "$CLAUDE_OUT" | grep -qF "must work from a clean checkout"
  # The Makefile wraps the native tool rather than replacing it.
  echo "$CLAUDE_OUT" | grep -qF "gofumpt"
  echo "$CLAUDE_OUT" | grep -qF "ruff"
}

# ────── issue routing (PR #96 review) ──────

# Two different rules — infra centralises, products keep their own tracker.
@test "issue routing distinguishes StumpCloud infra from stump.wtf products" {
  echo "$CLAUDE_OUT" | grep -qF "StumpCloud (infra) → one central tracker"
  echo "$CLAUDE_OUT" | grep -qF "their own repo's tracker"
}

# ────── reviewing (PR #96 review) ──────

@test "reviewers fix things in our repos and must post a summary comment" {
  echo "$CLAUDE_OUT" | grep -qF "Fix it rather than just flagging it"
  echo "$CLAUDE_OUT" | grep -qF "The comment is not optional"
  echo "$CLAUDE_OUT" | grep -qF "never push to a third party's branch"
}

# ────── worktrees defer to the harness (PR #96 review) ──────

# Claude Code keeps worktrees at .claude/worktrees/ INSIDE the repo, gitignored.
# The rule that matters is "never visible to git", not "never nested".
@test "worktree rule defers to the harness convention" {
  echo "$CLAUDE_OUT" | grep -qF ".claude/worktrees/"
  echo "$CLAUDE_OUT" | grep -qF "because the path is gitignored"
  run grep -cF "never nested inside it" <<< "$CLAUDE_OUT"
  [ "$output" -eq 0 ]
}

# ────── channels + Cairn (PR #96 review) ──────

@test "replies go back on the originating channel" {
  echo "$CLAUDE_OUT" | grep -qF "Always reply on the channel the request came in on"
}

# Joe wants the Signal backlog — the old "don't proactively message" rule is gone.
@test "Signal backlog is opt-out, not opt-in" {
  echo "$CLAUDE_OUT" | grep -qF "Send him a note when work lands, without waiting to be asked"
  run grep -cF "Do not proactively send Signal messages" <<< "$CLAUDE_OUT"
  [ "$output" -eq 0 ]
}

@test "Cairn is the escape hatch for large artifacts, and never for secrets" {
  echo "$CLAUDE_OUT" | grep -qF "cairn.stump.wtf"
  echo "$CLAUDE_OUT" | grep -qF "instead of pasting something huge"
  echo "$CLAUDE_OUT" | grep -qF "Never put a secret"
}

@test "Switchboard points at the skill instead of duplicating mechanics" {
  echo "$CLAUDE_OUT" | grep -qF "/switchboard"
}

@test "the chezmoi skill is referenced before editing managed files" {
  echo "$CLAUDE_OUT" | grep -qF "Load the \`/chezmoi\` skill"
}

# ────── attribution footers (PR #96 review) ──────

# The harness is known at apply time and templated in; the model is only known at
# runtime, so it stays a placeholder the agent fills in.
@test "footer names the harness per target and leaves the model to runtime" {
  echo "$CLAUDE_OUT" | grep -qF "using [Claude Code](https://claude.ai)."
  echo "$CRUSH_OUT"  | grep -qF "using [Crush](https://github.com/charmbracelet/crush)."
  # AGENTS.md has no harness, so it must not claim one.
  run grep -cF "using [Claude Code]" <<< "$AGENTS_OUT"
  [ "$output" -eq 0 ]
}

@test "footer requires a backticked model linked to OpenRouter" {
  echo "$CLAUDE_OUT" | grep -qF '[`<model>`](<openrouter-url>)'
  echo "$CLAUDE_OUT" | grep -qF "https://openrouter.ai/<vendor>/<model-slug>"
  echo "$CLAUDE_OUT" | grep -qF "say so in the body"
}

@test "the agent identity signs autonomously rather than on Joe's behalf" {
  local out
  out="$(chezmoi execute-template --source "$REPO_ROOT" <<'EOF'
{{ includeTemplate "agents/identity-joestump-agent.md" (merge (dict "harnessName" "Crush" "harnessUrl" "https://x") .) }}
EOF
)"
  grep -qF "This was posted autonomously by" <<< "$out"
  run grep -cF "Posted on behalf of" <<< "$out"
  [ "$output" -eq 0 ]
}

@test "the retired hand-maintained CRUSH.md is gone" {
  [ ! -e "$REPO_ROOT/dot_config/crush/CRUSH.md" ]
  [ -f "$REPO_ROOT/dot_config/crush/CRUSH.md.tmpl" ]
}
