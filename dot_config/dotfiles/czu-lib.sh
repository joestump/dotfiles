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
# Exactly one status token is printed on stdout so callers and tests can branch
# on the outcome: pulled | skip-local-branch | detached | nonff
czu_sync_branch() {
  _czu_dir=$1

  _czu_br=$(git -C "$_czu_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
    echo detached
    return 1
  }

  if git -C "$_czu_dir" ls-remote --exit-code --heads origin "$_czu_br" >/dev/null 2>&1; then
    # Best-effort: keep tracking correct so a bare `git pull` works next time.
    git -C "$_czu_dir" branch --set-upstream-to="origin/$_czu_br" "$_czu_br" >/dev/null 2>&1 || true
    if git -C "$_czu_dir" pull --ff-only origin "$_czu_br" >/dev/null 2>&1; then
      echo pulled
      return 0
    fi
    echo nonff
    return 1
  fi

  echo skip-local-branch
  return 0
}
