# Spaceship prompt config. OMZ sources custom/*.zsh BEFORE the theme loads
# (oh-my-zsh.sh: custom at ~line 209, theme at ~214), so these take effect.

# Always show the hostname so I can tell which machine I'm on (laptop, ie01, …).
SPACESHIP_HOST_SHOW=always

# No blank line above the prompt.
SPACESHIP_PROMPT_ADD_NEWLINE=false

# Two-line prompt: all the info on line 1, the prompt character alone on line 2.
SPACESHIP_PROMPT_SEPARATE_LINE=true

# Prompt character: a RANDOM cute Nerd Font glyph, re-rolled every shell start.
# (Anonymous function so `glyphs` stays local; SPACESHIP_CHAR_SYMBOL is global.)
() {
  local glyphs=(
    $''  # paw
    $''  # heart
    $''  # star
    $''  # rocket
    $''  # coffee
    $''  # smiley
    $''  # leaf
    $''  # music note
    $''  # gift
    $''  # magic wand
    $''  # spark
    $''  # moon
  )
  SPACESHIP_CHAR_SYMBOL="${glyphs[$((RANDOM % ${#glyphs} + 1))]} "
}
SPACESHIP_CHAR_COLOR_SUCCESS=magenta   # cuter than the default green
