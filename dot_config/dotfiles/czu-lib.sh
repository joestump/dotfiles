#!/usr/bin/env sh
# czu-lib.sh — sourceable helpers behind `czu` (the dotfiles sync + apply).
#
# Kept as a POSIX-sh library (not inline in executable_czu-run.zsh) so the
# sync logic is unit-testable under BATS. It is sourced by
# dot_config/dotfiles/executable_czu-run.zsh and by test/czu-lib.bats.
#
# THE MODEL (two checkouts, two roles):
#   production — chezmoi's default source dir (~/.local/share/chezmoi): the
#     clone czu renders $HOME from. Always upstream main, always clean. Nothing
#     and nobody edits it; czu_sync_prod enforces that every run.
#   workbench  — ~/src/dotfiles: an ordinary git repo where development
#     happens. Branches, dirty trees, worktrees — all fine, because czu never
#     reads it. Work reaches machines only by merging to main upstream.
#
# This replaced czu_sync_branch/czu_branch_drift (the one-shared-checkout
# model), whose stash-around-pull and drift-advisory machinery existed to
# accommodate applying $HOME from parked feature branches — the exact
# entanglement of workbench and production that made czu fail some way nearly
# every run. With production pinned to clean upstream main, sync is a
# fast-forward pull that has almost no ways to fail.

# czu_sync_prod DIR URL
# Ensure the production clone at DIR exists, sits on clean main, and is
# current with origin/main. URL is only used to create a missing clone.
#
# Exactly one status token on stdout so callers and tests can branch:
#   cloned        DIR did not exist; cloned fresh from URL (rc 0)
#   current       already level with origin/main; nothing pulled (rc 0)
#   synced        fast-forwarded onto origin/main (rc 0)
#   offline       fetch failed (no network); applying last-synced main (rc 0)
#   clone-failed  DIR missing and the clone did not succeed (rc 1)
#   dirty         uncommitted edits in DIR — someone edited production; the
#                 change belongs in the workbench (~/src/dotfiles) (rc 1)
#   wedged        not on main and could not switch to it (rc 1)
#   nonff         local main has commits origin/main lacks — someone committed
#                 in production, or upstream main was rewritten (rc 1)
#
# offline is deliberately rc 0: a laptop off the home network must still apply
# its last-synced tree — czu degrading to "render what we have" beats czu
# failing outright. dirty/nonff are deliberately NOT self-healed (a reset
# --hard would be safe for real production drift but destroys work if a
# confused session committed here instead of the workbench); the caller
# prints the recovery command and a human decides.
czu_sync_prod() {
  _czu_dir=$1
  _czu_url=$2

  if [ ! -d "$_czu_dir/.git" ]; then
    if [ -n "$_czu_url" ] && git clone --quiet -- "$_czu_url" "$_czu_dir" >/dev/null 2>&1; then
      echo cloned
      return 0
    fi
    echo clone-failed
    return 1
  fi

  if ! git -C "$_czu_dir" diff --quiet 2>/dev/null \
     || ! git -C "$_czu_dir" diff --cached --quiet 2>/dev/null \
     || [ -n "$(git -C "$_czu_dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then
    echo dirty
    return 1
  fi

  _czu_br=$(git -C "$_czu_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || _czu_br=""
  if [ "$_czu_br" != "main" ]; then
    # A parked or detached production clone is drift, not work: the tree is
    # clean (checked above), so switching back to main loses nothing.
    git -C "$_czu_dir" switch --quiet main >/dev/null 2>&1 || {
      echo wedged
      return 1
    }
  fi

  if ! git -C "$_czu_dir" fetch --quiet origin main >/dev/null 2>&1; then
    echo offline
    return 0
  fi

  _czu_behind=$(git -C "$_czu_dir" rev-list --count "HEAD..origin/main" 2>/dev/null) || _czu_behind=0
  if git -C "$_czu_dir" merge --ff-only --quiet origin/main >/dev/null 2>&1; then
    if [ "${_czu_behind:-0}" -gt 0 ]; then
      echo synced
    else
      echo current
    fi
    return 0
  fi

  echo nonff
  return 1
}

# czu_reassert_targets SRCDIR TARGET...
# Scoped `chezmoi apply --force` for targets that an APPLICATION also writes.
#
# chezmoi tracks the state it last wrote per target; when an app rewrites one
# of these files in place (Crush rewrites ~/.config/crush/crush.json during
# config migrations and TUI actions), every subsequent apply trips the
# changed-since-last-write guard. On a TTY that is an interactive prompt on
# EVERY czu; under the scheduled (no-TTY) timer the file is silently skipped
# instead — either way the render stops landing, forever, because answering
# the prompt once doesn't stop the app writing again.
#
# For a target listed here the RENDER is the whole truth, so the resolution is
# always "overwrite": verify the target first, and only when it differs
# force-apply just that target, before the main apply runs. The main apply
# then finds it clean and never needs to ask.
#
# SRCDIR is the production clone; it is passed explicitly (--source) so the
# reassert renders the same tree the main apply will, even mid-migration when
# the rendered chezmoi.toml still points somewhere else.
#
# One status token per target on stdout so callers and tests can branch:
#   current:<target>     already matches the render; nothing written
#   reasserted:<target>  differed (app rewrite or pending render change);
#                        overwritten with the render
#   failed:<target>      forced apply failed (also: target not managed);
#                        the main apply will surface the real error
# Returns 1 if any target failed, 0 otherwise. Callers should treat failure
# as advisory — the main apply is the authoritative error path.
czu_reassert_targets() {
  _czu_src=$1
  shift
  _czu_rrc=0
  for _czu_target in "$@"; do
    if chezmoi verify --source "$_czu_src" -- "$_czu_target" >/dev/null 2>&1; then
      echo "current:${_czu_target}"
    elif chezmoi apply --source "$_czu_src" --force -- "$_czu_target" >/dev/null 2>&1; then
      echo "reasserted:${_czu_target}"
    else
      echo "failed:${_czu_target}"
      _czu_rrc=1
    fi
  done
  return $_czu_rrc
}
