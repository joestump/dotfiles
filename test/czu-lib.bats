#!/usr/bin/env bats
# Tests for dot_config/dotfiles/czu-lib.sh — the branch-sync helper behind `czu`.
# The box runs from a fork and may sit on any branch, so czu_sync_branch must:
#   - fast-forward the current branch from origin when the fork has it,
#   - do so even when the branch has NO upstream tracking (the regression that
#     made `czu` die with "no tracking information"),
#   - skip cleanly (not fail) when the branch isn't on the fork yet,
#   - fail on a detached HEAD.
load test_helper

setup() {
  setup_stub_path
  export GIT_AUTHOR_NAME=czu GIT_AUTHOR_EMAIL=czu@test \
         GIT_COMMITTER_NAME=czu GIT_COMMITTER_EMAIL=czu@test

  export LIBFILE="$REPO_ROOT/dot_config/dotfiles/czu-lib.sh"
  export REMOTE="$BATS_TEST_TMPDIR/remote.git"   # stands in for the fork (origin)
  export WORK="$BATS_TEST_TMPDIR/work"           # the box's checkout

  git init --quiet --bare -b main "$REMOTE"
  git clone --quiet "$REMOTE" "$WORK"
  git -C "$WORK" commit --quiet --allow-empty -m init
  git -C "$WORK" push --quiet -u origin main
}

# Advance origin/<branch> by one commit via a throwaway clone.
advance_origin() {
  local branch="$1" scratch="$BATS_TEST_TMPDIR/scratch"
  rm -rf "$scratch"
  git clone --quiet "$REMOTE" "$scratch"
  git -C "$scratch" checkout --quiet "$branch"
  git -C "$scratch" commit --quiet --allow-empty -m "advance $branch"
  git -C "$scratch" push --quiet origin "$branch"
  rm -rf "$scratch"
}

@test "czu-lib.sh parses under sh -n and bash -n" {
  run sh -n "$LIBFILE";   [ "$status" -eq 0 ]
  run bash -n "$LIBFILE"; [ "$status" -eq 0 ]
}

@test "fast-forwards the current branch from the fork" {
  advance_origin main
  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "pulled" ]
  [ "$(git -C "$WORK" rev-list --count HEAD)" -eq 2 ]
}

@test "pulls even when the branch has no upstream tracking (the czu regression)" {
  # Put a two-commit branch on the fork, then check out a LOCAL branch of the
  # same name that is behind and has NO upstream configured.
  git -C "$WORK" checkout --quiet -b feature
  git -C "$WORK" commit --quiet --allow-empty -m base
  git -C "$WORK" push --quiet -u origin feature
  advance_origin feature                       # fork is now ahead by one
  git -C "$WORK" checkout --quiet main
  git -C "$WORK" branch --quiet -D feature
  git -C "$WORK" fetch --quiet origin
  git -C "$WORK" checkout --quiet -b feature --no-track "origin/feature~1"

  # Precondition: the local branch genuinely has no upstream.
  run git -C "$WORK" rev-parse --abbrev-ref 'feature@{upstream}'
  [ "$status" -ne 0 ]

  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "pulled" ]
  # ...and it repaired the tracking as a side effect.
  run git -C "$WORK" rev-parse --abbrev-ref 'feature@{upstream}'
  [ "$status" -eq 0 ]
  [ "$output" = "origin/feature" ]
}

@test "skips cleanly when the branch is not on the fork yet" {
  git -C "$WORK" checkout --quiet -b wip/local-only
  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "skip-local-branch" ]
}

@test "already up to date is a successful pull" {
  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "pulled" ]
}

@test "auto-stashes a dirty tree so an unrelated ff-pull still succeeds" {
  # Seed a tracked file and push it so local == origin (no divergence).
  echo "base" > "$WORK/README.local"
  git -C "$WORK" add -A && git -C "$WORK" commit --quiet -m "seed README.local"
  git -C "$WORK" push --quiet origin main
  advance_origin main                          # fork moves ahead (empty commit, unrelated)
  echo "more wip" >> "$WORK/README.local"      # local uncommitted (dirty) edit
  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "pulled" ]
  # Advanced to the new commit AND the local edit survived on top.
  [ "$(git -C "$WORK" rev-list --count HEAD)" -eq 3 ]
  run grep -q "more wip" "$WORK/README.local"
  [ "$status" -eq 0 ]
}

@test "keeps local edits in a stash (reports stash-conflict) when they collide with the pull" {
  # Both sides change the SAME file on the SAME lines -> pop conflicts.
  echo "base" > "$WORK/collide.txt"
  git -C "$WORK" add -A && git -C "$WORK" commit --quiet -m "seed collide.txt"
  git -C "$WORK" push --quiet origin main
  # Fork advances collide.txt...
  local scratch="$BATS_TEST_TMPDIR/scratch"; rm -rf "$scratch"
  git clone --quiet "$REMOTE" "$scratch"
  echo "theirs" > "$scratch/collide.txt"
  git -C "$scratch" commit --quiet -am "fork edits collide.txt"
  git -C "$scratch" push --quiet origin main
  rm -rf "$scratch"
  # ...and the box has a conflicting uncommitted edit to the same file.
  echo "mine" > "$WORK/collide.txt"

  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 1 ]
  [ "$output" = "stash-conflict" ]
  # The pull still landed (box advanced) and the edit is preserved in the stash.
  run git -C "$WORK" stash list
  [ -n "$output" ]
}

@test "fast-forwards while preserving non-conflicting local edits" {
  printf 'base\n' >"$WORK/local.txt"
  git -C "$WORK" add local.txt
  git -C "$WORK" commit --quiet -m "add local file"
  git -C "$WORK" push --quiet origin main
  printf 'local edit\n' >"$WORK/local.txt"
  advance_origin main

  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "pulled" ]
  [ "$(cat "$WORK/local.txt")" = "local edit" ]
  [ "$(git -C "$WORK" status --short -- local.txt)" = " M local.txt" ]
}

@test "fails on a detached HEAD" {
  git -C "$WORK" checkout --quiet --detach
  run bash -c '. "$LIBFILE"; czu_sync_branch "$WORK"'
  [ "$status" -eq 1 ]
  [ "$output" = "detached" ]
}

# --- czu_branch_drift ---------------------------------------------------------
# Advisory check that runs between sync and apply. It exists because czu applies
# whatever branch is checked out, and czu_sync_branch reports success both when a
# feature branch isn't on the fork yet and when it fast-forwards from its own
# stale counterpart — neither says anything about main. A box parked on a feature
# branch therefore rendered $HOME from a tree 43 commits behind main, silently,
# until the branch was merged+rewritten upstream and czu wedged on `nonff`.
# It must NEVER fail the run: in-flight feature-branch work still has to apply.

@test "drift: reports current when on main and level with origin/main" {
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "current" ]
}

@test "drift: reports how far main is behind origin/main" {
  advance_origin main
  advance_origin main
  git -C "$WORK" fetch --quiet origin
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "behind:2" ]
}

@test "drift: names the branch and the gap when parked off main (the 43-commit case)" {
  git -C "$WORK" checkout --quiet -b feat/parked
  advance_origin main
  advance_origin main
  advance_origin main
  git -C "$WORK" fetch --quiet origin
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "off-main:feat/parked:3" ]
}

@test "drift: a feature branch level with main is not warned about" {
  git -C "$WORK" checkout --quiet -b feat/fresh
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "off-main:feat/fresh:0" ]
}

@test "drift: reports detached HEAD without failing" {
  git -C "$WORK" checkout --quiet --detach
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "detached" ]
}

@test "drift: a missing origin/main reads as unknown, never as current" {
  git -C "$WORK" remote remove origin
  git -C "$WORK" update-ref -d refs/remotes/origin/main
  run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "drift: is advisory — it never returns non-zero, on any repo state" {
  # The whole point is that it cannot wedge czu the way czu_sync_branch can.
  for state in main detach nobranch; do
    case "$state" in
      detach)   git -C "$WORK" checkout --quiet --detach ;;
      nobranch) git -C "$WORK" checkout --quiet -b feat/x ;;
    esac
    run bash -c '. "$LIBFILE"; czu_branch_drift "$WORK"'
    [ "$status" -eq 0 ]
  done
  run bash -c '. "$LIBFILE"; czu_branch_drift "/nonexistent/path"'
  [ "$status" -eq 0 ]
}
