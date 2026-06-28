# Spaceship prompt config. OMZ sources custom/*.zsh BEFORE the theme loads
# (oh-my-zsh.sh: custom at ~line 209, theme at ~214), so these take effect.

# Always show the hostname so I can tell which machine I'm on (laptop, ie01, …).
SPACESHIP_HOST_SHOW=always

# No blank line above the prompt.
SPACESHIP_PROMPT_ADD_NEWLINE=false

# Two-line prompt: all the info on line 1, the prompt character alone on line 2.
SPACESHIP_PROMPT_SEPARATE_LINE=true

# Prompt character: a random zap/sparkle Nerd Font glyph (re-rolled each shell),
# pink, with a trailing space so it isn't jammed against the command you type.
() {
  local glyphs=(
    $''   # zap (bolt)
    $''   # sparkle (star)
    $''   # sparkle (star, outline)
  )
  SPACESHIP_CHAR_SYMBOL="${glyphs[$((RANDOM % ${#glyphs} + 1))]} "
}
SPACESHIP_CHAR_COLOR_SUCCESS=213   # pink (256-color); red still shows on error
