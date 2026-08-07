#!/usr/bin/env bats
# Regression guard for dot_gitconfig.tmpl — ~/.gitconfig carries the git commit
# identity (name + email), derived from whoami using the $USER / $USER-agent
# convention, plus global defaults (init.defaultBranch, pull.rebase, etc.).
# These tests render the template and assert against the OUTPUT (what git reads).
# A second group renders against synthetic data to prove identity is genuinely
# derived from the username, not hardcoded.
load test_helper

GIT_TMPL="$REPO_ROOT/dot_gitconfig.tmpl"

# Render the real template (real .chezmoidata.yaml) into a variable. Skips when
# chezmoi isn't installed.
_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$GIT_TMPL"
}

# Render with a specific .chezmoi.username by overriding the chezmoi data.
# This is what proves identity derives from whoami, not from a hardcoded value.
_render_as() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local username="$1"
  chezmoi execute-template --source "$REPO_ROOT" \
    --override-data "{\"chezmoi\":{\"username\":\"$username\"}}" \
    < "$GIT_TMPL"
}

# ────── source layout ──────

@test "git-config: source is a dot_ template at repo root" {
  [ -f "$GIT_TMPL" ]
  basename "$GIT_TMPL" | grep -q '^dot_gitconfig\.tmpl$'
}

@test "git-config: template hardcodes no identity values" {
  # No name/email may be baked in — everything derives from whoami.
  run grep -Eic 'joestump|agent@stump|joe@stump' "$GIT_TMPL"
  [ "$output" -eq 0 ]
}

# ────── rendered output: identity derivation ──────

@test "git-config: renders without error" {
  run _render
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "git-config: agent user gets agent identity" {
  run _render_as "joestump-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = joestump-agent"* ]]
  [[ "$output" == *"email = agent@stump.wtf"* ]]
}

@test "git-config: human user gets personal identity" {
  run _render_as "joestump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = joestump"* ]]
  [[ "$output" == *"email = joestump@stump.wtf"* ]]
}

@test "git-config: agent email strips suffix from any human name" {
  # The convention is <human>-agent; the agent email local-part is always
  # 'agent', regardless of the human name.
  run _render_as "alice-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = alice-agent"* ]]
  [[ "$output" == *"email = agent@stump.wtf"* ]]
}

@test "git-config: human email uses the OS login as local-part" {
  run _render_as "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = alice"* ]]
  [[ "$output" == *"email = alice@stump.wtf"* ]]
}

# ────── rendered output: global defaults ──────

@test "git-config: init.defaultBranch is main" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaultBranch = main"* ]]
}

@test "git-config: pull.rebase is true (never merge main into branch)" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"rebase = true"* ]]
}

@test "git-config: push.autoSetupRemote is true" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"autoSetupRemote = true"* ]]
}

@test "git-config: credential helper store for bootstrap" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"helper = store"* ]]
}

@test "git-config: GitHub gh auth credential helper present" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh auth git-credential"* ]]
}
