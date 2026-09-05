#!/usr/bin/env bats
# Regression tests for run_after_33-install-msgbrowse.sh.
#
# The bug: `brew outdated <name>` exits 1 when the named package IS outdated
# (and 0 only when current). The upgrade branch was written as
#
#   if brew outdated ... >/dev/null 2>&1 && [ -n "$(brew outdated ...)" ]; then
#
# so the exit-code half was false exactly when an upgrade existed, and every
# run fell through to "up to date". msgbrowse-desktop sat at 0.8.3 for weeks
# while the tap published 0.8.25 — the upgrade path never fired once.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_33-install-msgbrowse.sh.tmpl"

@test "msgbrowse: renders and is valid bash" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$SCRIPT' | bash -n"
  [ "$status" -eq 0 ]
}

@test "msgbrowse: brew upgrade is decided by brew outdated OUTPUT, not its exit code" {
  # The only acceptable gate is [ -n "$(brew outdated ...)" ]. Any `brew
  # outdated ... &&` condition reintroduces the dead-code bug.
  run grep -E '^[^#]*brew outdated .*&&' "$SCRIPT"
  [ "$status" -ne 0 ]
  run grep -F 'if [ -n "$(brew outdated' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "msgbrowse: brew_sync upgrades when brew outdated exits 1 with output" {
  # Simulate Homebrew's real contract: rc=1 + the package name on stdout
  # means outdated. The logic must take the upgrade branch.
  # Single-binary stub: the script calls `brew list|outdated|upgrade`, so the
  # stub dispatches on $1. outdated emulates the real contract: rc=1 + name
  # on stdout when outdated, rc=0 + no output when current.
  brew() {
    case "$1" in
      list) return 0 ;;
      outdated) echo "stump-wtf/tap/msgbrowse-desktop"; return 1 ;;
      upgrade) echo UPGRADED; return 0 ;;
      install) return 0 ;;
      *) return 127 ;;
    esac
  }
  item() { shift; echo "$*"; }
  warn() { echo "WARN: $*"; }
  source_brew_sync
  out=$(brew_sync "--cask" "stump-wtf/tap/msgbrowse-desktop" "msgbrowse-desktop")
  [ "$?" -eq 0 ]
  [[ "$out" == *"upgraded"* ]]
}

@test "msgbrowse: brew_sync reports current when brew outdated exits 0 with no output" {
  brew() {
    case "$1" in
      list) return 0 ;;
      outdated) return 0 ;;
      upgrade) echo UPGRADED; return 0 ;;
      install) return 0 ;;
      *) return 127 ;;
    esac
  }
  item() { shift; echo "$*"; }
  warn() { echo "WARN: $*"; }
  source_brew_sync
  out=$(brew_sync "--cask" "stump-wtf/tap/msgbrowse-desktop" "msgbrowse-desktop")
  [ "$?" -eq 0 ]
  [[ "$out" == *"up to date"* ]]
}

@test "msgbrowse: the old exit-code gate would have skipped the upgrade" {
  # Pins the bug itself. Under the old condition, rc=1 + output (the exact
  # "outdated" signal) evaluates false — the upgrade never runs.
  brew_outdated() { echo pkg; return 1; }
  old_gate() { brew_outdated >/dev/null 2>&1 && [ -n "$(brew_outdated 2>/dev/null)" ]; }
  run old_gate
  [ "$status" -ne 0 ]
}

# Extract just the brew_sync function from the rendered script so the tests
# exercise the shipped logic, not a restatement of it. Callers define brew
# stub functions first; brew_sync resolves them at call time.
source_brew_sync() {
  local rendered
  # --override-data forces the darwin branch: the script is darwin-only, so a
  # plain render on a linux runner contains no brew_sync at all.
  rendered=$(chezmoi execute-template --override-data '{"chezmoi":{"os":"darwin"}}' \
    --source "$REPO_ROOT" < "$SCRIPT")
  eval "$(printf '%s\n' "$rendered" | sed -n '/^brew_sync()/,/^}/p')"
}
