#!/usr/bin/env sh
# czu-lib.sh — sourceable helpers behind `czu` (the dotfiles sync + apply).
#
# Kept as a POSIX-sh library (not inline in executable_czu-run.zsh) so the
# branch-sync logic is unit-testable under BATS without invoking chezmoi. It is
# sourced by dot_config/dotfiles/executable_czu-run.zsh and by test/czu-lib.bats.

# czu_sync_branch DIR
# Fast-forward the currently checked-out branch of the git repo at DIR from its
# counterpart on `origin` (this box runs from a fork, so origin == the fork).
#
# The box may sit on any branch — main or an in-flight feature branch — so this
# never assumes upstream tracking is configured (a fresh, not-yet-pushed branch
# has none, which is exactly what used to make `git pull --ff-only` hard-fail
# with "no tracking information"):
#
#   branch exists on the fork -> `git pull --ff-only origin <branch>`, and the
#                                branch's upstream is (re)pointed at origin so an
#                                ordinary `git pull` works next time too
#   branch NOT on the fork yet -> nothing to sync; skip cleanly (rc 0)
#   detached HEAD / non-ff / git error -> failure (rc 1)
#
# A dirty working tree — uncommitted edits made directly in the chezmoi source
# dir — is the single most common way this box gets stuck: `git pull --ff-only`
# hard-fails ("Your local changes would be overwritten by merge") the instant an
# incoming commit touches a locally-modified file, even though `git status` says
# the branch "can be fast-forwarded". Left alone the tree never clears, so every
# subsequent sync fails too — a permanent deadlock. czu_sync_branch defuses this
# by auto-stashing local changes around the pull: set them aside, fast-forward,
# then restore them on top. Nothing is ever discarded — if restoring conflicts
# (a local edit and an incoming commit changed the same lines), the stash is
# KEPT and we report `stash-conflict` so the box advances and the conflict is
# visible, instead of staying stuck forever.
#
# Exactly one status token is printed on stdout so callers and tests can branch
# on the outcome: pulled | skip-local-branch | detached | nonff | stash-conflict
czu_sync_branch() {
  _czu_dir=$1

  _czu_br=$(git -C "$_czu_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
    echo detached
    return 1
  }

  if git -C "$_czu_dir" ls-remote --exit-code --heads origin "$_czu_br" >/dev/null 2>&1; then
    # Best-effort: keep tracking correct so a bare `git pull` works next time.
    git -C "$_czu_dir" branch --set-upstream-to="origin/$_czu_br" "$_czu_br" >/dev/null 2>&1 || true

    # Stash a dirty tree (tracked + untracked) so it can't block the ff pull.
    _czu_stashed=0
    if ! git -C "$_czu_dir" diff --quiet 2>/dev/null \
       || ! git -C "$_czu_dir" diff --cached --quiet 2>/dev/null \
       || [ -n "$(git -C "$_czu_dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then
      if git -C "$_czu_dir" stash push --include-untracked --quiet -m czu-autostash >/dev/null 2>&1; then
        _czu_stashed=1
      fi
    fi

    if git -C "$_czu_dir" pull --ff-only origin "$_czu_br" >/dev/null 2>&1; then
      if [ "$_czu_stashed" -eq 1 ]; then
        # Restore local edits on top of the freshly pulled tree.
        if ! git -C "$_czu_dir" stash pop --quiet >/dev/null 2>&1; then
          # Conflict: keep the stash (do not drop it) so nothing is lost.
          echo stash-conflict
          return 1
        fi
      fi
      echo pulled
      return 0
    fi

    # Pull failed for some other reason — restore the tree we set aside.
    [ "$_czu_stashed" -eq 1 ] && git -C "$_czu_dir" stash pop --quiet >/dev/null 2>&1
    echo nonff
    return 1
  fi

  echo skip-local-branch
  return 0
}

# czu_branch_drift DIR
# Report how far the checked-out branch has drifted from `origin/main`, so czu can
# say so out loud before it applies.
#
# Why this exists: czu applies whatever branch happens to be checked out, and two
# of czu_sync_branch's outcomes are silently benign — `skip-local-branch` (rc 0)
# when a local feature branch isn't on the fork yet, and `pulled` when a feature
# branch fast-forwards from its own stale counterpart. Neither says anything about
# `main`. A box left parked on a feature branch therefore keeps rendering the whole
# home directory from that branch, indefinitely, with no signal. That is exactly
# how this laptop ended up applying a tree 43 commits behind main — and, because
# the branch had since been merged and rewritten on the fork, eventually wedging
# czu with `nonff` on every run.
#
# Deliberately ADVISORY, never fatal: it always returns 0. In-flight feature-branch
# work is legitimate and must still apply. The goal is only that you cannot drift
# dozens of commits without being told.
#
# Exactly one status token on stdout, so callers and tests can branch on it:
#   current | behind:<n> | off-main:<branch>:<n> | detached | unknown
czu_branch_drift() {
  _czu_dir=$1

  _czu_dbr=$(git -C "$_czu_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
    echo detached
    return 0
  }

  # No origin/main to compare against (fresh clone, odd remote) — say so rather
  # than guessing; a missing ref must not read as "you're current".
  if ! git -C "$_czu_dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    echo unknown
    return 0
  fi

  _czu_behind=$(git -C "$_czu_dir" rev-list --count "HEAD..origin/main" 2>/dev/null) || _czu_behind=""
  [ -n "$_czu_behind" ] || { echo unknown; return 0; }

  if [ "$_czu_dbr" != "main" ]; then
    echo "off-main:${_czu_dbr}:${_czu_behind}"
    return 0
  fi

  [ "$_czu_behind" -gt 0 ] && echo "behind:${_czu_behind}" || echo current
  return 0
}
