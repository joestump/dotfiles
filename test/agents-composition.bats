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
    "## Secrets" \
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

@test "the identity role follows whoami (agentIdentity defaults empty)" {
  grep -q '^agentIdentity: ""$' "$REPO_ROOT/.chezmoidata.yaml"
  # Resolve the ROLE exactly as the compositions do ($USER / $USER-agent
  # convention), then assert the matching overlay was composed —
  # deterministic on every box and in CI.
  local who
  who="$(chezmoi execute-template --source "$REPO_ROOT" \
    '{{ $u := .agentIdentity | default .chezmoi.username }}{{ hasSuffix "-agent" $u | ternary "agent" "human" }}')"
  if [ "$who" = "agent" ]; then
    echo "$CLAUDE_OUT" | grep -qF "your **own** accounts"
    ! echo "$CLAUDE_OUT" | grep -qF "Posted on behalf of"
  else
    echo "$CLAUDE_OUT" | grep -qF "Posted on behalf of"
    echo "$CRUSH_OUT"  | grep -qF "Posted on behalf of"
  fi
}

@test "both role overlays exist so the printf lookup can never miss" {
  [ -f "$REPO_ROOT/.chezmoitemplates/agents/identity-human.md" ]
  [ -f "$REPO_ROOT/.chezmoitemplates/agents/identity-agent.md" ]
}

# The agent signs as itself; using Joe's footer would misattribute the work.
@test "the agent role drops the on-behalf-of footer" {
  local agent_id
  agent_id="$(cat "$REPO_ROOT/.chezmoitemplates/agents/identity-agent.md")"
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

# Worktree isolation is the DEFAULT, not a fallback for busy checkouts: agents
# share these repos with each other and with Joe, and the checkout they land in
# is routinely parked mid-work on someone else's dirty branch.
@test "worktree isolation is mandatory, not advisory" {
  local rule
  for rule in \
    "Every code-change task starts in its own worktree" \
    "Never commit from the primary checkout" \
    "Never stash-and-switch" \
    "One worktree per concern" \
    "Remove it when the work lands"
  do
    echo "$CLAUDE_OUT" | grep -qF "$rule" || { echo "missing worktree rule: $rule"; return 1; }
  done
  # The old permissive framing must not survive alongside the strict rule.
  run grep -cF 'Use a worktree whenever you need a second checkout' <<< "$CLAUDE_OUT"
  [ "$output" -eq 0 ]
}

# ────── Gitea/GitHub canonicity ──────

# Which copy is real is discovered from repo METADATA, never from a hardcoded
# list of repo names — a static table in an agent file rots the moment a repo
# is added, and the agent has no way to notice it went stale.
@test "canonical host is discovered from repo topics, not a static list" {
  local rule
  for rule in \
    "canonical-gitea" \
    "canonical-github" \
    "downstream-mirror" \
    "declares it in its own **topics**" \
    "Topics are **not** replicated by the push mirror" \
    "You are required to maintain these topics"
  do
    echo "$CLAUDE_OUT" | grep -qF "$rule" || { echo "missing canonicity rule: $rule"; return 1; }
  done
  # Both hosts need a concrete, non-destructive way to add one topic.
  echo "$CLAUDE_OUT" | grep -qF 'gh repo edit'
  echo "$CLAUDE_OUT" | grep -qF '/topics/<topic>'
}

# The flow is not universally Gitea→GitHub; asserting the direction is
# per-repo is what stops "it's on GitHub, so GitHub is the mirror".
@test "canonicity is per-repo, not inferred from the hostname" {
  echo "$CLAUDE_OUT" | grep -qF "Do not guess from the hostname"
  echo "$CLAUDE_OUT" | grep -qF "A few repos are GitHub-native"
}

# A clone made from the mirror looks completely normal; the remote is the only
# tell, so the check has to happen before the first push.
@test "agents must read the remote before pushing" {
  echo "$CLAUDE_OUT" | grep -qF "git remote -v"
  echo "$CLAUDE_OUT" | grep -qF "git remote set-url origin"
  echo "$CLAUDE_OUT" | grep -qF "do not push"
}

# GitHub org names cannot contain dots, so stump.wtf ↔ stump-wtf is a live
# footgun: the hyphen form silently addresses the throwaway mirror.
@test "the stump.wtf / stump-wtf spelling trap is called out" {
  echo "$CLAUDE_OUT" | grep -qF 'GitHub org names cannot contain dots'
  echo "$CLAUDE_OUT" | grep -qF 'stump-wtf'
}

@test "repo creation requires the canonical-host topic on both hosts" {
  echo "$CLAUDE_OUT" | grep -qF "The canonical-host topic — mandatory"
  echo "$CLAUDE_OUT" | grep -qF "set them on both hosts"
}

# This repo mandates worktrees and Claude Code puts them inside .claude/, so the
# path must be ignored here or every session offers to commit its own checkout.
@test "the harness worktree path is gitignored in this repo" {
  grep -qF '.claude/worktrees/' "$REPO_ROOT/.gitignore"
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
    "as a collaborator with **write** access" \
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

@test "Family contacts (incl. the operator) render from .contacts into every target" {
  local n
  for n in "+12062257886" "+15419137301" "+17347090582"; do
    echo "$CLAUDE_OUT" | grep -qF "$n" || { echo "missing from CLAUDE.md: $n"; return 1; }
    echo "$CRUSH_OUT"  | grep -qF "$n" || { echo "missing from CRUSH.md: $n";  return 1; }
    echo "$AGENTS_OUT" | grep -qF "$n" || { echo "missing from AGENTS.md: $n"; return 1; }
  done
}

@test "no phone number is hardcoded in the agents templates (data is the source)" {
  # .chezmoidata.yaml's contacts block is the single source of truth. PR #123
  # templated Chelsea's and Jon's numbers but left the operator's inline twice;
  # a literal number here is exactly the drift that splits when data changes.
  run grep -rEn '\+[0-9]{8,}' "$REPO_ROOT/.chezmoitemplates/agents/"
  [ "$status" -ne 0 ]
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
{{ includeTemplate "agents/identity-agent.md" (merge (dict "harnessName" "Crush" "harnessUrl" "https://x") .) }}
EOF
)"
  grep -qF "This was posted autonomously by" <<< "$out"
  run grep -cF "Posted on behalf of" <<< "$out"
  [ "$output" -eq 0 ]
}

# ────── secret hygiene ──────

# The motivating failure: an agent ran `git remote -v` for an unrelated reason
# and a PAT embedded in the remote URL landed in the transcript. The rules must
# name that class of command, not just say "don't print secrets".
@test "secret rules name the commands that leak credentials incidentally" {
  local rule
  for rule in \
    "A secret that reaches your context is compromised" \
    "git remote -v" \
    "kubectl get secret -o yaml" \
    "set -x" \
    "Grep for the key *name*" \
    "Report it plainly in your summary and rotate it"
  do
    echo "$CLAUDE_OUT" | grep -qF "$rule" || { echo "missing secret rule: $rule"; return 1; }
  done
}

# The whole point of shipping a snippet is that an agent will paste it verbatim.
# A subtly broken one is worse than none: the first version of this helper used a
# greedy sed that reduced sha256sum's "<hash>  -" output to "-", so EVERY pair of
# secrets compared equal — a silent false "match". Extract the function from the
# RENDERED rules and actually run it.
@test "the documented fingerprint helper works when extracted from the render" {
  local fn out
  fn="$(printf '%s\n' "$CLAUDE_OUT" | sed -n '/^sfp() {/,/^}/p')"
  [ -n "$fn" ] || { echo "sfp() not found in rendered rules"; return 1; }

  out="$(sh -c "$fn"'
    A="ghp_EXAMPLEfake000000000000000000000000"
    B="ghp_DIFFERENTfake00000000000000000000000"
    printf "fp=%s\n" "$(sfp "$A")"
    [ "$(sfp "$A")" = "$(sfp "$A")" ] && echo same-match || echo same-BROKEN
    [ "$(sfp "$A")" = "$(sfp "$B")" ] && echo diff-BROKEN || echo diff-differs
  ')"

  grep -q 'same-match'   <<< "$out" || { echo "identical secrets did not match: $out"; return 1; }
  grep -q 'diff-differs' <<< "$out" || { echo "different secrets compared equal: $out"; return 1; }
  # A real fingerprint, not an artifact of the output format.
  grep -qE 'fp=[0-9a-f]{12}$' <<< "$out" || { echo "bad fingerprint: $out"; return 1; }
  # And it must never echo the input back.
  run grep -c 'EXAMPLEfake' <<< "$out"
  [ "$output" -eq 0 ]
}

# Every hasher branch must agree, because which one runs is decided by the box:
# stock macOS has shasum but no sha256sum, most Linux has both.
# Which hasher runs is decided by the box — stock macOS has shasum but no
# sha256sum — and the three print the digest in three different layouts:
#   sha256sum         "<hash>  -"
#   shasum -a 256     "<hash>  -"
#   openssl dgst      "SHA2-256(stdin)= <hash>"
# So the extractor, not the hasher, is the fragile part. Pull the awk program out
# of the rendered helper (so this tracks the docs rather than duplicating them)
# and assert every available backend normalises to the same fingerprint.
@test "the fingerprint is identical across every hasher's output format" {
  local fn script want ex got h
  fn="$(printf '%s\n' "$CLAUDE_OUT" | sed -n '/^sfp() {/,/^}/p')"
  [ -n "$fn" ] || { echo "sfp() not found in rendered rules"; return 1; }

  script="$fn
sfp \"\$1\""
  want="$(sh -c "$script" _ secret-under-test)"
  [ -n "$want" ] || { echo "helper produced no fingerprint"; return 1; }

  ex="$(printf '%s\n' "$fn" | sed -n "s/^.*| awk '\(.*\)'[[:space:]]*$/\1/p")"
  [ -n "$ex" ] || { echo "could not extract the awk extractor from the helper"; return 1; }

  local ran=0
  while IFS= read -r h; do
    command -v "${h%% *}" >/dev/null 2>&1 || continue
    got="$(printf %s secret-under-test | $h | awk "$ex")"
    [ "$got" = "$want" ] || { echo "$h -> '$got', want '$want'"; return 1; }
    ran=$((ran + 1))
  done <<'HASHERS'
sha256sum
shasum -a 256
openssl dgst -sha256
HASHERS

  # Guard against the whole loop being skipped and the test passing vacuously.
  [ "$ran" -ge 2 ] || { echo "only $ran hasher(s) exercised"; return 1; }
}

@test "the documented redaction strips credentials from remote URLs" {
  local red
  red="$(printf '%s\n' \
      'agent	https://user:ghp_SECRETVALUE@github.com/o/r.git (fetch)' \
      'origin	https://gitea.stump.rocks/joestump/dotfiles.git (fetch)' \
    | sed -E 's#://([^:/@]+):[^@]*@#://\1:***@#')"
  run grep -c 'ghp_SECRETVALUE' <<< "$red"
  [ "$output" -eq 0 ]
  grep -qF 'https://user:***@github.com/o/r.git' <<< "$red"
  # A credential-free remote must survive untouched.
  grep -qF 'https://gitea.stump.rocks/joestump/dotfiles.git' <<< "$red"
}

@test "the retired hand-maintained CRUSH.md is gone" {
  [ ! -e "$REPO_ROOT/dot_config/crush/CRUSH.md" ]
  [ -f "$REPO_ROOT/dot_config/crush/CRUSH.md.tmpl" ]
}
