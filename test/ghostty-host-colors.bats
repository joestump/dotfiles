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

@test ".chezmoidata.yaml ghostty section is valid YAML" {
  python3 -c '
import yaml, sys
with open("'"$REPO_ROOT"'/.chezmoidata.yaml") as f:
    data = yaml.safe_load(f)
g = data.get("ghostty", {})
assert "hostColors" in g, "ghostty.hostColors missing"
assert "fallbackPalette" in g, "ghostty.fallbackPalette missing"
assert len(g["hostColors"]) >= 1, "hostColors empty"
assert len(g["fallbackPalette"]) >= 1, "fallbackPalette empty"
for entry in g["hostColors"]:
    assert "host" in entry, "hostColors entry missing host"
    assert "color" in entry, "hostColors entry missing color"
    assert entry["color"].startswith("#"), f"color must be hex: {entry}"
for c in g["fallbackPalette"]:
    assert c.startswith("#"), f"palette color must be hex: {c}"
'
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
