#!/usr/bin/env bats
# Regression tests for run_onchange_after_31-retire-claude-plugins.sh.
#
# The installer never uninstalls a plugin that leaves claude-plugins.tsv, so
# retiring stumpcloud@stumpcloud-skills (migrated into stump.wtf/skills on
# 2026-09-15) needs its own step, and that step must not be able to resurrect
# or widen into anything destructive.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_31-retire-claude-plugins.sh.tmpl"
TSV="$REPO_ROOT/dot_config/dotfiles/claude-plugins.tsv.tmpl"

@test "retire-plugins: renders and is valid bash" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$SCRIPT' | bash -n"
  [ "$status" -eq 0 ]
}

@test "retire-plugins: every retired plugin is absent from claude-plugins.tsv" {
  # A name in both lists would be uninstalled and reinstalled on every apply.
  retired=$(sed -n 's/^RETIRED="\(.*\)"$/\1/p' "$SCRIPT")
  [ -n "$retired" ]
  for p in $retired; do
    # Non-comment lines only: the tsv's comments may name the retired plugin.
    run bash -c "grep -v '^[[:space:]]*#' '$TSV' | grep -F '$p'"
    [ "$status" -ne 0 ]
  done
}

@test "retire-plugins: the replacement plugin IS in claude-plugins.tsv" {
  run grep -E '^https://gitea\.stump\.rocks/stump\.wtf/skills\.git[[:space:]]+stump-wtf@stump-wtf-skills$' "$TSV"
  [ "$status" -eq 0 ]
}

@test "retire-plugins: the cache purge is guarded against empty path components" {
  run grep -E '\[ -n "\$pname" \] && \[ -n "\$mp" \]' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "retire-plugins: matches the installed listing by exact token, not substring" {
  run grep -E 'grep -qxF "\$plugin"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "retire-plugins: the old Crush clone is retired via .chezmoiremove, and the new external exists" {
  run grep -qxF '.config/crush/skills-ext/stumpcloud-skills' "$REPO_ROOT/.chezmoiremove"
  [ "$status" -eq 0 ]
  run grep -qF '[".config/crush/skills-ext/stump-wtf-skills"]' "$REPO_ROOT/.chezmoiexternal.toml"
  [ "$status" -eq 0 ]
  run grep -qF '[".config/crush/skills-ext/stumpcloud-skills"]' "$REPO_ROOT/.chezmoiexternal.toml"
  [ "$status" -ne 0 ]
}

@test "retire-plugins: crush.json skills_paths points at the new clone only" {
  run grep -c 'skills-ext/stump-wtf-skills/skills' "$REPO_ROOT/dot_config/crush/crush.json.tmpl"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep -c 'skills-ext/stumpcloud-skills' "$REPO_ROOT/dot_config/crush/crush.json.tmpl"
  [ "$output" -eq 0 ]
}
