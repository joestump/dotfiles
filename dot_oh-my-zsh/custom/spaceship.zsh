# Spaceship prompt config. OMZ sources custom/*.zsh BEFORE the theme loads
# (oh-my-zsh.sh: custom at ~line 209, theme at ~214), so these take effect.

# Always show the hostname so I can tell which machine I'm on (laptop, ie01, …).
# Spaceship otherwise only shows it over SSH.
SPACESHIP_HOST_SHOW=always

# Drop the blank line Spaceship inserts above each prompt.
SPACESHIP_PROMPT_ADD_NEWLINE=false
