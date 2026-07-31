#!/usr/bin/env bats
# Locks in the two-checkout model at the render level.
#
# PRODUCTION is chezmoi's default source dir (~/.local/share/chezmoi), kept on
# clean upstream main by czu_sync_prod; the WORKBENCH is ~/src/dotfiles, which
# chezmoi never reads. The whole model rests on three render facts, each of
# which a well-meaning future change could quietly regress:
#   1. chezmoi.toml sets NO sourceDir (default location == production);
#   2. czinit bootstraps with a bare `init --apply` (no --source), so a fresh
#      node's clone and config agree by default;
#   3. the Claude guard hooks bake the workbench + production paths via
#      homeDir, NOT .chezmoi.sourceDir (mid-migration that variable can still
#      point at the old shared checkout).
load test_helper

CHEZMOI_TOML="$REPO_ROOT/dot_config/chezmoi/chezmoi.toml.tmpl"
CHEZMOI_ZSH="$REPO_ROOT/dot_oh-my-zsh/custom/chezmoi.zsh.tmpl"
EDIT_GUARD="$REPO_ROOT/dot_claude/hooks/executable_chezmoi-edit-guard.sh.tmpl"
COMMIT_GUARD="$REPO_ROOT/dot_claude/hooks/executable_chezmoi-commit-guard.sh.tmpl"

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
}

_render_tmpl() {
  local tmpl="$1"
  env -i HOME="$HOME" PATH="$PATH" \
    bash -c 'chezmoi execute-template --source "$0" < "$1"' "$REPO_ROOT" "$tmpl"
}

@test "chezmoi.toml renders WITHOUT sourceDir (default source dir is production)" {
  run _render_tmpl "$CHEZMOI_TOML"
  [ "$status" -eq 0 ]
  ! grep -E '^\s*sourceDir\s*=' <<<"$output" >/dev/null
}

@test "chezmoi.toml keeps autoCommit and autoPush off" {
  run _render_tmpl "$CHEZMOI_TOML"
  [ "$status" -eq 0 ]
  grep -E 'autoCommit\s*=\s*false' <<<"$output" >/dev/null
  grep -E 'autoPush\s*=\s*false' <<<"$output" >/dev/null
}

@test "czinit bootstraps with a bare init --apply (no --source)" {
  run _render_tmpl "$CHEZMOI_ZSH"
  [ "$status" -eq 0 ]
  grep -F -- 'init --apply' <<<"$output" >/dev/null
  ! grep -F -- 'init --source' <<<"$output" >/dev/null
}

@test "edit guard bakes workbench and production paths via homeDir, not sourceDir" {
  run _render_tmpl "$EDIT_GUARD"
  [ "$status" -eq 0 ]
  grep -F -- "WORKBENCH=\"$HOME/src/dotfiles\"" <<<"$output" >/dev/null
  grep -F -- "PROD=\"$HOME/.local/share/chezmoi\"" <<<"$output" >/dev/null
}

@test "commit guard watches the workbench, not the production clone" {
  run _render_tmpl "$COMMIT_GUARD"
  [ "$status" -eq 0 ]
  grep -F -- "CHEZMOI_SRC=\"$HOME/src/dotfiles\"" <<<"$output" >/dev/null
}
