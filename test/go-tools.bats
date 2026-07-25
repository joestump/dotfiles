#!/usr/bin/env bats
# Tests for go-tools.txt — ensures all entries are valid go install paths.
# Regression guard: the harness entry was gitea.stump.rocks/stump.wtf/harness@latest
# (root package, no Go files) instead of .../cmd/harness@latest, causing
# "module found but does not contain package" on every `czu` run.
load test_helper

GO_TOOLS="$REPO_ROOT/dot_config/dotfiles/go-tools.txt"

@test "go-tools.txt exists" {
  [ -f "$GO_TOOLS" ]
}

@test "harness entry uses cmd/harness subpath (not root package)" {
  grep -q 'gitea.stump.rocks/stump.wtf/harness/cmd/harness@latest' "$GO_TOOLS"
}

@test "no harness entry points to the bare root module" {
  ! grep -qx 'gitea.stump.rocks/stump.wtf/harness@latest' "$GO_TOOLS"
}

@test "all non-comment non-blank lines contain @version or are bare module paths" {
  while IFS= read -r line; do
    # Skip comments and blank lines
    case "$line" in ''|'#'*) continue;; esac
    # Every entry must have at least one slash (module path)
    [[ "$line" == */* ]]
  done < "$GO_TOOLS"
}
