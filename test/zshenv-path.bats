#!/usr/bin/env bats
# Tests for dot_zshenv — ~/.local/bin on PATH in NON-interactive shells.
#
# The defect these guard: PATH used to be composed only in the OMZ custom
# files (env.zsh, go.zsh, zz-path.zsh), all of which load from
# `source $ZSH/oh-my-zsh.sh` in .zshrc — and .zshrc is read by interactive
# shells only. So `ssh host '<cmd>'` and every non-interactive automation ran
# without ~/.local/bin and resolved a tool to a stale ~/go/bin build, or to
# nothing at all. Measured on kitt 09/12/2026: `zsh -lc command -v harness`
# returned nothing while a current binary sat in ~/.local/bin.
#
# Every test below runs zsh under `env -i`. That is load-bearing, not
# tidiness: a zsh that inherits the caller's PATH already contains
# ~/.local/bin, so these would all pass against a dot_zshenv that did
# nothing whatsoever.

load test_helper

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/bin" "$FAKE_HOME/go/bin"
  cp "$REPO_ROOT/dot_zshenv" "$FAKE_HOME/.zshenv"
}

# A non-interactive, non-login zsh with no inherited environment. ~/go/bin is
# seeded into the starting PATH so the ordering assertion has something real
# to order against.
clean_path() {
  env -i HOME="$FAKE_HOME" ZDOTDIR="$FAKE_HOME" \
    PATH="$FAKE_HOME/go/bin:/usr/bin:/bin" \
    zsh -c 'print -l $path'
}

@test "a non-interactive zsh has ~/.local/bin on PATH" {
  run clean_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE_HOME/.local/bin"* ]]
}

@test "a non-interactive zsh has ~/bin on PATH" {
  run clean_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE_HOME/bin"* ]]
}

@test "~/.local/bin precedes ~/go/bin, so a stale go install cannot win" {
  local out local_idx go_idx
  out="$(clean_path)"
  local_idx="$(printf '%s\n' "$out" | grep -nxF "$FAKE_HOME/.local/bin" | cut -d: -f1)"
  go_idx="$(printf '%s\n' "$out" | grep -nxF "$FAKE_HOME/go/bin" | cut -d: -f1)"
  [ -n "$local_idx" ]
  [ -n "$go_idx" ]
  [ "$local_idx" -lt "$go_idx" ]
}

@test "re-sourcing does not duplicate entries (typeset -U holds)" {
  # This is what lets custom/env.zsh, go.zsh and zz-path.zsh keep their own
  # identical prepends unchanged — they become no-ops rather than conflicts.
  local n
  n="$(env -i HOME="$FAKE_HOME" ZDOTDIR="$FAKE_HOME" \
        PATH="$FAKE_HOME/go/bin:/usr/bin:/bin" \
        zsh -c 'source $ZDOTDIR/.zshenv; source $ZDOTDIR/.zshenv; print -l $path' \
      | grep -cxF "$FAKE_HOME/.local/bin")"
  [ "$n" -eq 1 ]
}

@test "dot_zshenv carries PATH only — never secret-derived exports" {
  # .zshenv runs on EVERY shell, including every scp and rsync. The OpenBao
  # exports in custom/env.zsh must never migrate here; that would be a bigger
  # problem than the bug this file fixes.
  run grep -nE 'VAULT_|_TOKEN|_API_KEY|OPENBAO|secrets-static' "$REPO_ROOT/dot_zshenv"
  [ "$status" -ne 0 ]
}
