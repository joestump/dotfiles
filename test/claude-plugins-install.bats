#!/usr/bin/env bats
# Regression tests for run_after_31-install-claude-plugins.sh.
#
# Two bugs, both of which made a freshly pushed skill silently never reach the
# harnesses — no error, just an "ok" tick and stale content:
#
#   1. `claude plugin list` is a HUMAN listing ("  ❯ **name@marketplace**",
#      followed by indented Version/Scope/Status lines). The old whole-line
#      `grep -qxF` match therefore never matched, so EVERY plugin took the
#      "not installed" branch and the HEAD-moved refresh branch was dead code.
#   2. `claude` caches a plugin at cache/<mp>/<plugin>/<version>/ and that
#      directory survives `plugin uninstall`, so reinstalling at an unchanged
#      version reuses the stale copy.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_31-install-claude-plugins.sh.tmpl"

@test "claude-plugins: renders and is valid bash" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$SCRIPT' | bash -n"
  [ "$status" -eq 0 ]
}

@test "claude-plugins: extracts name@marketplace instead of matching whole lines" {
  # The decorated listing must still yield an exact match, or the refresh branch
  # can never fire.
  listing=$'Installed plugins:\n\n  \xe2\x9d\xaf **personal@claude-personal**\n      Version: 0.2.0\n      Scope: user\n\n  \xe2\x9d\xaf **qmd@qmd**\n      Version: 0.1.0\n'
  run bash -c "printf '%s' \"\$1\" | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+' | grep -qxF 'personal@claude-personal'" _ "$listing"
  [ "$status" -eq 0 ]
}

@test "claude-plugins: the old whole-line match would NOT have matched" {
  # Pins the bug itself, so nobody "simplifies" the extraction back.
  listing=$'Installed plugins:\n\n  \xe2\x9d\xaf **personal@claude-personal**\n      Version: 0.2.0\n'
  run bash -c "printf '%s' \"\$1\" | grep -qxF 'personal@claude-personal'" _ "$listing"
  [ "$status" -ne 0 ]
}

@test "claude-plugins: extraction ignores the indented metadata lines" {
  listing=$'  \xe2\x9d\xaf **personal@claude-personal**\n      Version: 0.2.0\n      Status: disabled\n'
  run bash -c "printf '%s' \"\$1\" | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+' | wc -l | tr -d ' '" _ "$listing"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "claude-plugins: the refresh branch purges the version-keyed cache" {
  run grep -E 'rm -rf "\$HOME/\.claude/plugins/cache/\$mp/\$pname"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "claude-plugins: the cache purge is guarded against empty path components" {
  # A malformed tsv line must never let this become rm -rf on a short path.
  run grep -E '\[ -n "\$pname" \] && \[ -n "\$mp" \]' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "claude-plugins: purge happens BEFORE the reinstall, not after" {
  purge=$(grep -n 'rm -rf "\$HOME/\.claude/plugins/cache' "$SCRIPT" | head -1 | cut -d: -f1)
  reinstall=$(grep -n 'step "\$plugin → ' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$purge" ] && [ -n "$reinstall" ]
  [ "$purge" -lt "$reinstall" ]
}

# Third bug (dotfiles#124): `marketplace add` was chained to `marketplace update`
# with `||`. `add` exits 0 for an already-registered marketplace, so the update
# never ran and the cached marketplace.json froze at its first-cloned commit —
# permanently, because a plugin that never installs keeps retaking that branch.

@test "claude-plugins: marketplace add and update are not chained with ||" {
  # Pins the bug. `add ... || ... update` must never come back.
  run grep -E 'marketplace add .*\|\|.*marketplace update' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "claude-plugins: marketplace update runs unconditionally in the install branch" {
  # Both commands present, each terminated with its own `|| true`.
  run grep -E 'claude plugin marketplace add "\$src" </dev/null >/dev/null 2>&1 \|\| true' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -E 'claude plugin marketplace update "\$mp" </dev/null >/dev/null 2>&1 \|\| true' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "claude-plugins: the marketplace refresh precedes the install it feeds" {
  update=$(grep -n 'claude plugin marketplace update "\$mp"' "$SCRIPT" | head -1 | cut -d: -f1)
  install=$(grep -n 'step "\$plugin" -- claude plugin install' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$update" ] && [ -n "$install" ]
  [ "$update" -lt "$install" ]
}

@test "claude-plugins: a zero-exit 'add' still lets the update run" {
  # Behavioural proof of the fix against stubs: the old `||` form skipped the
  # update whenever add succeeded; the new form must always reach it.
  tmp="$BATS_TEST_TMPDIR/marker"
  run bash -c '
    claude() {
      case "$2 $3" in
        "marketplace add") return 0 ;;                      # already registered
        "marketplace update") echo updated >>"'"$tmp"'" ;;
      esac
    }
    claude plugin marketplace add https://example/x >/dev/null 2>&1 || true
    claude plugin marketplace update x >/dev/null 2>&1 || true
  '
  [ "$status" -eq 0 ]
  [ -s "$tmp" ]
}
