#!/usr/bin/env bats
# Tests for scripts/lint-shell.sh — the shell lint gate.
#
# This exists because the gate silently under-covered for months. `make lint`
# globbed '.chezmoiscripts/*.sh', which matches nothing: every apply-time
# script there is a '*.sh.tmpl'. CI had a render-based step, but it lived only
# in the workflow (so local and CI could disagree) and it piped chezmoi into
# shellcheck without pipefail, so a template that failed to render lint clean.
# Each test below pins one of those failure modes shut.
load test_helper

SCRIPT="$REPO_ROOT/scripts/lint-shell.sh"

# Build a throwaway chezmoi source dir that is also a git repo, with the real
# lint script copied in. Lets the behavioural tests break a template without
# touching this repo's working tree.
_fixture() {
  local dir="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$dir/scripts" "$dir/.chezmoiscripts"
  cp "$SCRIPT" "$dir/scripts/lint-shell.sh"
  git -C "$dir" init -q
  git -C "$dir" config user.email lint@example.com
  git -C "$dir" config user.name lint
  printf '%s\n' "$dir"
}

_commit() { git -C "$1" add -A && git -C "$1" -c commit.gpgsign=false commit -qm fixture; }

@test "lint-shell: make exposes lint-shell and it runs the script" {
  run grep -qE '^lint-shell:' "$REPO_ROOT/Makefile"
  [ "$status" -eq 0 ]
  run grep -qF 'scripts/lint-shell.sh' "$REPO_ROOT/Makefile"
  [ "$status" -eq 0 ]
}

@test "lint-shell: CI calls the make target rather than inlining the globs" {
  # The drift this whole change is about: CI must not carry its own copy of
  # the file list, or the two can disagree again.
  run grep -qF 'make lint-shell' "$REPO_ROOT/.gitea/workflows/ci.yml"
  [ "$status" -eq 0 ]
  run grep -qF "git ls-files 'scripts/*.sh'" "$REPO_ROOT/.gitea/workflows/ci.yml"
  [ "$status" -ne 0 ]
}

@test "lint-shell: the template glob matches every tracked .sh.tmpl" {
  # '*.sh.tmpl', not '.chezmoiscripts/*.sh' — the original bug.
  run grep -qF "git ls-files '*.sh.tmpl'" "$SCRIPT"
  [ "$status" -eq 0 ]
  # Sanity: there really are templates that the old glob missed.
  local n
  n=$(cd "$REPO_ROOT" && git ls-files '.chezmoiscripts/*.sh.tmpl' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ]
}

@test "lint-shell: the render matrix covers both OS and both identity gates" {
  # Templates gate on .chezmoi.os and on the '-agent' login suffix. A single
  # render only ever sees one branch of each, so the matrix is the coverage.
  run grep -qF '"os":"darwin"' "$SCRIPT"; [ "$status" -eq 0 ]
  run grep -qF '"os":"linux"' "$SCRIPT";  [ "$status" -eq 0 ]
  run grep -qF '"agentIdentity":"lintuser"' "$SCRIPT";       [ "$status" -eq 0 ]
  run grep -qF '"agentIdentity":"lintuser-agent"' "$SCRIPT"; [ "$status" -eq 0 ]
}

@test "lint-shell: a clean source tree passes" {
  command -v chezmoi shellcheck >/dev/null 2>&1 || skip "chezmoi/shellcheck not installed"
  local dir; dir=$(_fixture)
  cat > "$dir/.chezmoiscripts/run_after_10-ok.sh.tmpl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "{{ .chezmoi.os }}"
EOF
  _commit "$dir"
  run "$dir/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
}

@test "lint-shell: a bug in an OS-gated branch this host is NOT is still caught" {
  command -v chezmoi shellcheck >/dev/null 2>&1 || skip "chezmoi/shellcheck not installed"
  local dir; dir=$(_fixture)
  # The faulty line renders only when .chezmoi.os is the OS we are not running
  # on, so a single-render lint would miss it on every machine.
  local other=linux
  [ "$(uname -s)" = "Linux" ] && other=darwin
  cat > "$dir/.chezmoiscripts/run_after_10-gated.sh.tmpl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{{- if eq .chezmoi.os "$other" }}
rm -rf \$UNQUOTED/*
{{- end }}
echo done
EOF
  _commit "$dir"
  run "$dir/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SC2115"* || "$output" == *"SC2086"* ]]
}

@test "lint-shell: a template that FAILS to render is an error, not a silent pass" {
  command -v chezmoi shellcheck >/dev/null 2>&1 || skip "chezmoi/shellcheck not installed"
  local dir; dir=$(_fixture)
  cat > "$dir/.chezmoiscripts/run_after_10-broken.sh.tmpl" <<'EOF'
#!/usr/bin/env bash
{{ .noSuchKey.nested }}
EOF
  _commit "$dir"
  run "$dir/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"render failed"* ]]
}

@test "lint-shell: a template that renders EMPTY is an error, not a silent pass" {
  command -v chezmoi shellcheck >/dev/null 2>&1 || skip "chezmoi/shellcheck not installed"
  local dir; dir=$(_fixture)
  # Everything behind a gate that is false on every variant: no shell at all.
  cat > "$dir/.chezmoiscripts/run_after_10-empty.sh.tmpl" <<'EOF'
{{- if eq .chezmoi.os "plan9" -}}
#!/usr/bin/env bash
echo hi
{{- end -}}
EOF
  _commit "$dir"
  run "$dir/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rendered empty"* ]]
}

@test "lint-shell: identical renders across variants are reported once" {
  command -v chezmoi shellcheck >/dev/null 2>&1 || skip "chezmoi/shellcheck not installed"
  local dir; dir=$(_fixture)
  # No gates, so all four variants render byte-identically and the finding
  # must not be repeated once per variant.
  cat > "$dir/.chezmoiscripts/run_after_10-ungated.sh.tmpl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo $UNQUOTED
EOF
  _commit "$dir"
  run "$dir/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'SC2086 (info)')" -eq 1 ]
}
