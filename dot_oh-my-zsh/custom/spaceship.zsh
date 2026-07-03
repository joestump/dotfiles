# Spaceship prompt config. OMZ sources custom/*.zsh BEFORE the theme loads
# (oh-my-zsh.sh: custom at ~line 209, theme at ~214), so these take effect.

# Always show the hostname so I can tell which machine I'm on (laptop, ie01, …).
SPACESHIP_HOST_SHOW=always

# Always show the username too. Spaceship's default (`true`) only shows it locally
# "if needed" (su/root) but ALWAYS over SSH — which is why the username appeared on
# ie01 (an SSH session) but not the laptop (a local session). `always` makes it
# consistent everywhere, and gives the vault lock below a stable anchor to sit after.
SPACESHIP_USER_SHOW=always

# No blank line above the prompt.
SPACESHIP_PROMPT_ADD_NEWLINE=false

# Two-line prompt: all the info on line 1, the prompt character alone on line 2.
SPACESHIP_PROMPT_SEPARATE_LINE=true

# Prompt character: a random glyph from $PROMPT_GLYPHS (defined in ~/.zshrc),
# pink, with a trailing space so it isn't jammed against the command you type.
() {
  local glyphs
  if (( ${#PROMPT_GLYPHS} )); then
    glyphs=( "${PROMPT_GLYPHS[@]}" )
  else
    glyphs=( $'' $'' $'' )   # fallback: zap, star, heart
  fi
  SPACESHIP_CHAR_SYMBOL="${glyphs[$((RANDOM % ${#glyphs} + 1))]} "
}
SPACESHIP_CHAR_COLOR_SUCCESS=213   # pink (256-color); red still shows on error

# The docker_compose section prints a cryptic per-container status letter
# (docker-compose ps → "MM" = two running containers), not a version. Noise —
# the docker section already shows the engine version. Turn it off.
SPACESHIP_DOCKER_COMPOSE_SHOW=false

# ---- Vault Agent lock -------------------------------------------------------
# A single padlock right after the username: green (theme green) = the Vault Agent
# is up and rendering secrets; red = it's down (run `vault-agent start` / re-login).
# NOTE: this reflects the AGENT being up, not whether the OIDC token is still valid —
# see the note in commit for a stricter "needs re-login" heartbeat option.
SPACESHIP_VAULT_SYMBOL_OK="${SPACESHIP_VAULT_SYMBOL_OK=$''}"    #  fa-lock (closed = secure)
SPACESHIP_VAULT_SYMBOL_BAD="${SPACESHIP_VAULT_SYMBOL_BAD=$''}"  #  fa-unlock (open = exposed)
SPACESHIP_VAULT_COLOR_OK="${SPACESHIP_VAULT_COLOR_OK=green}"          # named → the terminal theme's green
SPACESHIP_VAULT_COLOR_BAD="${SPACESHIP_VAULT_COLOR_BAD=red}"          # named → the terminal theme's red

spaceship_vault() {
  local ok=1
  if [[ "$OSTYPE" == darwin* ]]; then
    launchctl list 2>/dev/null | grep -q 'rocks\.stump\.vault-agent' || ok=0
  else
    systemctl --user is-active --quiet vault-agent 2>/dev/null || ok=0
  fi
  if (( ok )); then
    spaceship::section --color "$SPACESHIP_VAULT_COLOR_OK"  "$SPACESHIP_VAULT_SYMBOL_OK"
  else
    spaceship::section --color "$SPACESHIP_VAULT_COLOR_BAD" "$SPACESHIP_VAULT_SYMBOL_BAD"
  fi
}

# Insert `vault` right after `user` in the prompt order. spaceship fills in its
# default order only AFTER this file loads (the theme loads after $ZSH_CUSTOM), so do
# it once the array exists — from a cheap, idempotent precmd — instead of freezing the
# whole ~60-section default list here.
autoload -Uz add-zsh-hook
_spaceship_insert_vault() {
  (( ${SPACESHIP_PROMPT_ORDER[(Ie)vault]} )) && return   # already inserted
  local i=${SPACESHIP_PROMPT_ORDER[(Ie)user]}
  if (( i )); then
    SPACESHIP_PROMPT_ORDER=( ${SPACESHIP_PROMPT_ORDER[1,i]} vault ${SPACESHIP_PROMPT_ORDER[i+1,-1]} )
  else
    SPACESHIP_PROMPT_ORDER=( vault $SPACESHIP_PROMPT_ORDER )
  fi
}
add-zsh-hook precmd _spaceship_insert_vault
