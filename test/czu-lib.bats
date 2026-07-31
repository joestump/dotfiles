#!/usr/bin/env bats
# Tests for dot_config/dotfiles/czu-lib.sh — the sync helpers behind `czu`.
#
# Two checkouts, two roles: czu renders $HOME from the PRODUCTION clone
# (chezmoi's default source dir), which czu_sync_prod must keep on clean
# upstream main — creating it when missing, healing a parked/detached HEAD,
# degrading to "apply what we have" when offline, and refusing (with a
# distinct token) when someone edited or committed to production directly.
# The workbench (~/src/dotfiles) is deliberately invisible to these helpers.
load test_helper

setup() {
  setup_stub_path
  export GIT_AUTHOR_NAME=czu GIT_AUTHOR_EMAIL=czu@test \
         GIT_COMMITTER_NAME=czu GIT_COMMITTER_EMAIL=czu@test

  export LIBFILE="$REPO_ROOT/dot_config/dotfiles/czu-lib.sh"
  export REMOTE="$BATS_TEST_TMPDIR/remote.git"   # stands in for upstream (origin)
  export PROD="$BATS_TEST_TMPDIR/prod"           # the production clone

  git init --quiet --bare -b main "$REMOTE"
  local seed="$BATS_TEST_TMPDIR/seed"
  git clone --quiet "$REMOTE" "$seed"
  git -C "$seed" commit --quiet --allow-empty -m init
  git -C "$seed" push --quiet -u origin main
  rm -rf "$seed"
}

# Advance origin/main by one commit via a throwaway clone.
advance_origin() {
  local scratch="$BATS_TEST_TMPDIR/scratch"
  rm -rf "$scratch"
  git clone --quiet "$REMOTE" "$scratch"
  git -C "$scratch" commit --quiet --allow-empty -m "advance main"
  git -C "$scratch" push --quiet origin main
  rm -rf "$scratch"
}

clone_prod() {
  git clone --quiet "$REMOTE" "$PROD"
}

@test "czu-lib.sh parses under sh -n and bash -n" {
  run sh -n "$LIBFILE";   [ "$status" -eq 0 ]
  run bash -n "$LIBFILE"; [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# czu_sync_prod — creation
# ---------------------------------------------------------------------------

@test "sync: clones production fresh when the directory is missing" {
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "cloned" ]
  [ "$(git -C "$PROD" symbolic-ref --short HEAD)" = "main" ]
}

@test "sync: missing directory and no URL is clone-failed, not a crash" {
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" ""'
  [ "$status" -eq 1 ]
  [ "$output" = "clone-failed" ]
}

@test "sync: missing directory and an unreachable URL is clone-failed" {
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$BATS_TEST_TMPDIR/nope.git"'
  [ "$status" -eq 1 ]
  [ "$output" = "clone-failed" ]
}

# ---------------------------------------------------------------------------
# czu_sync_prod — the happy path
# ---------------------------------------------------------------------------

@test "sync: fast-forwards a stale production clone onto origin/main" {
  clone_prod
  advance_origin
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "synced" ]
  [ "$(git -C "$PROD" rev-parse HEAD)" = "$(git -C "$PROD" rev-parse origin/main)" ]
}

@test "sync: a current clone reads current, not synced" {
  clone_prod
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "current" ]
}

# ---------------------------------------------------------------------------
# czu_sync_prod — self-healing drift (clean tree, wrong ref)
# ---------------------------------------------------------------------------

@test "sync: switches a parked (clean) production clone back to main and syncs" {
  clone_prod
  git -C "$PROD" switch --quiet -c parked
  advance_origin
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "synced" ]
  [ "$(git -C "$PROD" symbolic-ref --short HEAD)" = "main" ]
}

@test "sync: recovers a detached HEAD back onto main" {
  clone_prod
  git -C "$PROD" checkout --quiet --detach
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "current" ]
  [ "$(git -C "$PROD" symbolic-ref --short HEAD)" = "main" ]
}

# ---------------------------------------------------------------------------
# czu_sync_prod — refusals (production was edited; never self-heal these)
# ---------------------------------------------------------------------------

@test "sync: an untracked file in production is dirty, and survives untouched" {
  clone_prod
  echo stray > "$PROD/stray.txt"
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 1 ]
  [ "$output" = "dirty" ]
  [ -f "$PROD/stray.txt" ]
}

@test "sync: a staged file in production is dirty" {
  clone_prod
  echo edited > "$PROD/edited.txt"
  git -C "$PROD" add edited.txt
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 1 ]
  [ "$output" = "dirty" ]
}

@test "sync: dirty wins over parked — never switch branches around local edits" {
  clone_prod
  git -C "$PROD" switch --quiet -c parked
  echo stray > "$PROD/stray.txt"
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 1 ]
  [ "$output" = "dirty" ]
  [ "$(git -C "$PROD" symbolic-ref --short HEAD)" = "parked" ]
}

@test "sync: local commits on production main are nonff, and are NOT discarded" {
  clone_prod
  git -C "$PROD" commit --quiet --allow-empty -m "committed in production"
  advance_origin
  local_head="$(git -C "$PROD" rev-parse HEAD)"
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 1 ]
  [ "$output" = "nonff" ]
  [ "$(git -C "$PROD" rev-parse HEAD)" = "$local_head" ]
}

@test "sync: unswitchable checkout is wedged" {
  clone_prod
  git -C "$PROD" checkout --quiet --detach
  git -C "$PROD" branch --quiet -D main
  git -C "$PROD" remote remove origin   # no DWIM source for `git switch main`
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 1 ]
  [ "$output" = "wedged" ]
}

# ---------------------------------------------------------------------------
# czu_sync_prod — offline degradation
# ---------------------------------------------------------------------------

@test "sync: unreachable origin is offline (rc 0) — czu still applies" {
  clone_prod
  git -C "$PROD" remote set-url origin "$BATS_TEST_TMPDIR/gone.git"
  run bash -c '. "$LIBFILE"; czu_sync_prod "$PROD" "$REMOTE"'
  [ "$status" -eq 0 ]
  [ "$output" = "offline" ]
}

# ---------------------------------------------------------------------------
# czu_reassert_targets — scoped `chezmoi apply --force` for targets an app
# also writes (Crush rewrites its own crush.json, tripping chezmoi's
# changed-since-last-write prompt on every apply thereafter). All chezmoi
# interaction is stubbed; these tests pin the verify-before-force order, the
# explicit --source (the production clone), the scoping of the forced apply
# to exactly the named target, and the one-token-per-target output contract.
# ---------------------------------------------------------------------------

# Stub chezmoi: logs every invocation, then branches on subcommand and target
# basename — a target under */clean/* verifies clean, anything else dirty; an
# apply of a target under */broken/* fails.
stub_chezmoi() {
  make_stub chezmoi 'echo "$*" >> "$STUB_BIN/chezmoi.calls"
case "$1:${!#}" in
  verify:*/clean/*) exit 0 ;;
  verify:*)         exit 1 ;;
  apply:*/broken/*) exit 1 ;;
  apply:*)          exit 0 ;;
esac
exit 0'
}

@test "reassert: a clean target reads current and is never force-applied" {
  stub_chezmoi
  run bash -c '. "$LIBFILE"; czu_reassert_targets "$PROD" "$HOME/clean/crush.json"'
  [ "$status" -eq 0 ]
  [ "$output" = "current:$HOME/clean/crush.json" ]
  ! grep -q '^apply' "$STUB_BIN/chezmoi.calls"
}

@test "reassert: a dirty target is force-applied from the production source, scoped to that target" {
  stub_chezmoi
  run bash -c '. "$LIBFILE"; czu_reassert_targets "$PROD" "$HOME/dirty/crush.json"'
  [ "$status" -eq 0 ]
  [ "$output" = "reasserted:$HOME/dirty/crush.json" ]
  grep -qF -- "apply --source $PROD --force -- $HOME/dirty/crush.json" "$STUB_BIN/chezmoi.calls"
  grep -qF -- "verify --source $PROD -- $HOME/dirty/crush.json" "$STUB_BIN/chezmoi.calls"
}

@test "reassert: a failed forced apply reads failed and returns 1" {
  stub_chezmoi
  run bash -c '. "$LIBFILE"; czu_reassert_targets "$PROD" "$HOME/broken/crush.json"'
  [ "$status" -eq 1 ]
  [ "$output" = "failed:$HOME/broken/crush.json" ]
}

@test "reassert: emits one token per target and keeps going past a failure" {
  stub_chezmoi
  run bash -c '. "$LIBFILE"; czu_reassert_targets "$PROD" \
    "$HOME/clean/a.json" "$HOME/broken/b.json" "$HOME/dirty/c.json"'
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "current:$HOME/clean/a.json" ]
  [ "${lines[1]}" = "failed:$HOME/broken/b.json" ]
  [ "${lines[2]}" = "reasserted:$HOME/dirty/c.json" ]
}
