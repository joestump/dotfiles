#!/usr/bin/env bats
# Tests for dot_oh-my-zsh/custom/terminal-hygiene.zsh — the precmd hook that
# resets mouse-reporting modes a crashed TUI left enabled. The interesting
# assertions are on the BYTES emitted: a missing or wrong DECRST sequence looks
# fine in review and only shows up as garbage in someone's prompt.
load test_helper

SRC="$REPO_ROOT/dot_oh-my-zsh/custom/terminal-hygiene.zsh"

@test "terminal-hygiene: source is plain zsh, not a template" {
  [ -f "$SRC" ]
  # Nothing in here needs chezmoi data; a .tmpl would re-render every apply.
  [ ! -e "$SRC.tmpl" ]
  run grep -c '{{' "$SRC"
  [ "$output" -eq 0 ]
}

@test "terminal-hygiene: parses as valid zsh" {
  run zsh -n "$SRC"
  [ "$status" -eq 0 ]
}

@test "terminal-hygiene: registers the reset on precmd" {
  grep -q 'autoload -Uz add-zsh-hook' "$SRC"
  grep -q 'add-zsh-hook precmd _term_reset_input_modes' "$SRC"
}

@test "terminal-hygiene: sourcing the file leaves a zero exit status" {
  # A file whose last statement is falsy makes the whole ZSH_CUSTOM source
  # non-zero at startup, which trips error-checking prompts.
  run zsh -c "source '$SRC'; echo rc=\$?"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]]
}

@test "terminal-hygiene: disables every mouse-reporting mode we can be left in" {
  # 1000 X11 click, 1002 button-drag, 1003 any-motion, 1004 focus,
  # 1005 UTF-8 coords, 1006 SGR coords, 1015 urxvt coords. SGR (1006) is the one
  # bubbletea apps use and the one that produced "66;96;23M" in the prompt.
  local mode
  for mode in 1000 1002 1003 1004 1005 1006 1015; do
    grep -q "\[?${mode}l" "$SRC" || {
      echo "mode $mode is never disabled" >&2
      return 1
    }
  done
}

@test "terminal-hygiene: the precmd path emits the reset only to a tty" {
  # Guarded on [[ -t 1 ]], so a non-interactive or redirected shell writes
  # nothing — otherwise every captured command output gains escape bytes.
  run zsh -c "source '$SRC'; _term_reset_input_modes"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "terminal-hygiene: the precmd path does NOT touch alt-screen or paste modes" {
  # ?1049 (alternate screen) and ?2004 (bracketed paste) are owned by the
  # running program and by zle respectively. Resetting them every prompt can
  # eat legitimate output; they belong to treset, the manual escape hatch.
  local fn
  fn=$(sed -n '/^_term_reset_input_modes()/,/^}/p' "$SRC")
  [ -n "$fn" ]
  [[ "$fn" != *"1049"* ]]
  [[ "$fn" != *"2004"* ]]
}

@test "terminal-hygiene: treset exists and does the full cleanup" {
  grep -q '^treset()' "$SRC"
  local fn
  fn=$(sed -n '/^treset()/,/^}/p' "$SRC")
  [[ "$fn" == *"1049l"* ]]   # leave the alternate screen
  [[ "$fn" == *"2004h"* ]]   # hand bracketed paste back to zle
  [[ "$fn" == *"?25h"* ]]    # show the cursor again
  [[ "$fn" == *"_term_reset_input_modes"* ]]
}

@test "terminal-hygiene: treset is defined for an interactive shell" {
  run zsh -c "source '$SRC'; whence -w treset"
  [ "$status" -eq 0 ]
  [[ "$output" == *"treset: function"* ]]
}
