#!/usr/bin/env bats
# Tests for dot_oh-my-zsh/custom/ghostty-host-colors.zsh.tmpl — the OSC 11
# host-coloring hook. Validates template rendering, zsh syntax of the rendered
# output, and that the data section in .chezmoidata.yaml is well-formed.
load test_helper

TMPL="$REPO_ROOT/dot_oh-my-zsh/custom/ghostty-host-colors.zsh.tmpl"

_render() {
  chezmoi execute-template --source "$REPO_ROOT" < "$TMPL"
}

@test "template renders without error" {
  run _render
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "rendered script parses as valid zsh" {
  run _render
  [ "$status" -eq 0 ]
  # Write rendered output to a temp file and syntax-check it.
  local rendered="$BATS_TEST_TMPDIR/ghostty-host-colors.zsh"
  printf '%s\n' "$output" > "$rendered"
  run zsh -n "$rendered"
  [ "$status" -eq 0 ]
}

@test "rendered script contains the precmd hook registration" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-zsh-hook precmd _ghostty_host_color"* ]]
}

@test "rendered script contains the chpwd hook registration" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-zsh-hook chpwd _ghostty_host_color"* ]]
}

@test "rendered script gates on TERM_PROGRAM=ghostty" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *'TERM_PROGRAM" == "ghostty"'* ]]
}

@test "rendered script emits OSC 11 escape" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *'\e]11;'* ]]
}

@test "known hosts from .chezmoidata.yaml render into exact-match blocks" {
  run _render
  [ "$status" -eq 0 ]
  # dagda, tars, cloud01, lir are explicit non-glob entries
  [[ "$output" == *'"dagda"'* ]]
  [[ "$output" == *'"tars"'* ]]
  [[ "$output" == *'"cloud01"'* ]]
  [[ "$output" == *'"lir"'* ]]
}

@test "glob patterns render into the glob-match block, not exact-match" {
  run _render
  [ "$status" -eq 0 ]
  # *.stump.rocks should NOT appear in an exact-match == comparison
  # (it would always fail since no hostname literally equals "*.stump.rocks")
  local exact_match_line
  exact_match_line=$(printf '%s\n' "$output" | grep -F '== "*.stump.rocks"' || true)
  [ -z "$exact_match_line" ]
  # But it SHOULD appear in the glob-match section (unquoted pattern)
  [[ "$output" == *'*.stump.rocks'* ]]
}

@test "fallback palette renders as a zsh array" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"local -a palette="* ]]
  # At least one fallback color present
  [[ "$output" == *"#1c1e2d"* ]]
}

@test ".chezmoidata.yaml ghostty section is well-formed" {
  # Validated through chezmoi's own YAML parse rather than PyYAML: chezmoi is
  # the actual consumer of this data, and CI installs plain python3 with no
  # `yaml` module (see .gitea/workflows/ci.yml), so an `import yaml` here fails
  # the bats job on every run regardless of whether the data is correct.
  run chezmoi execute-template --source "$REPO_ROOT" '
{{- range .ghostty.hostColors }}host={{ .host }} color={{ .color }}
{{ end }}
{{- range .ghostty.fallbackPalette }}palette={{ . }}
{{ end }}'
  [ "$status" -eq 0 ]

  # Both lists are non-empty...
  [[ "$output" == *"host="* ]]
  [[ "$output" == *"palette="* ]]

  # ...every hostColors entry carries both keys, and every color is a 6-digit
  # hex literal. A missing key renders as the empty string, which these catch.
  local line
  while IFS= read -r line; do
    case "$line" in
      host=*)
        [[ "$line" =~ ^host=[^[:space:]]+\ color=\#[0-9a-fA-F]{6}$ ]] ;;
      palette=*)
        [[ "$line" =~ ^palette=\#[0-9a-fA-F]{6}$ ]] ;;
    esac
  done <<< "$output"
}

@test "function does nothing when TERM_PROGRAM is not ghostty" {
  run _render
  [ "$status" -eq 0 ]
  local rendered="$BATS_TEST_TMPDIR/ghostty-host-colors.zsh"
  printf '%s\n' "$output" > "$rendered"
  # Stub add-zsh-hook (normally provided by OMZ) and source the function.
  # Leave TERM_PROGRAM unset so the guard returns early with no output.
  run zsh -c '
    add-zsh-hook() { :; }
    source "'"$rendered"'"
    HOST="testhost"
    _ghostty_host_color
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Runtime behaviour. The tests above only ever assert on the RENDERED TEXT, and
# the one test that executed the function took the non-ghostty early return —
# so the whole colour-resolution body was uncovered. That is exactly how
# `##host[i+1]` (invalid zsh math: `##x` is the ordinal of the literal char x,
# so zsh read `##h` and choked on `ost[i+1]`) shipped green while erroring on
# every single prompt for every host not named in .chezmoidata.yaml.
# ---------------------------------------------------------------------------

# Source the rendered hook with TERM_PROGRAM unset (so the load-time call is a
# no-op), then invoke it for $1 with the ghostty gate on. stderr is folded into
# stdout so a math/parse error can't hide behind a passing exit status.
_color_for() {
  local rendered="$BATS_TEST_TMPDIR/ghostty-host-colors.zsh"
  if [ ! -f "$rendered" ]; then
    _render > "$rendered"
  fi
  zsh -c '
    add-zsh-hook() { :; }
    unset TERM_PROGRAM
    source "'"$rendered"'"
    TERM_PROGRAM=ghostty
    HOST="'"$1"'"
    _ghostty_host_color
  ' 2>&1
}

@test "a known host resolves to its explicit colour" {
  run _color_for dagda
  [ "$status" -eq 0 ]
  [[ "$output" == *"#1e1e2e"* ]]
}

@test "a glob entry matches an FQDN host" {
  run _color_for box.stump.rocks
  [ "$status" -eq 0 ]
  [[ "$output" == *"#181926"* ]]
}

@test "an unknown host falls back to the palette without erroring" {
  # The `##host[i+1]` regression: this emitted
  # "bad math expression: operator expected at \`ost[i+1]) ...'" on every
  # prompt and set no colour at all.
  run _color_for someunknownbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"bad math expression"* ]]
  [[ "$output" != *"parse error"* ]]
  # An OSC 11 sequence carrying one of the palette colours.
  [[ "$output" == *$'\e]11;#'* ]]
  [[ "$output" =~ \#[0-9a-f]{6} ]]
}

@test "the fallback colour is stable for the same host" {
  run _color_for anotherunknownbox
  [ "$status" -eq 0 ]
  local first="$output"
  run _color_for anotherunknownbox
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ -n "$first" ]
}

@test "the hook returns 0 on the ghostty path" {
  # precmd hooks run between the command and the prompt, so a non-zero return
  # here is a status leak into anything that inspects $? — and the hook is also
  # called at load time, which would make `source` of this file fail. Assert it
  # for the unknown-host path, which is the one that used to blow up.
  local rendered="$BATS_TEST_TMPDIR/ghostty-host-colors.zsh"
  _render > "$rendered"
  run zsh -c '
    add-zsh-hook() { :; }
    unset TERM_PROGRAM
    source "'"$rendered"'"
    TERM_PROGRAM=ghostty
    HOST="yetanotherunknownbox"
    _ghostty_host_color >/dev/null 2>&1
    exit $?
  '
  [ "$status" -eq 0 ]
}
