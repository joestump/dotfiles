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

# ---- Vault Agent lock (a dock icon; see the status dock below) --------------
# A single padlock: green (theme green) = the Vault Agent is up and rendering secrets;
# red = it's down (run `vault-agent start` / re-login). NOTE: reflects the AGENT being
# up, not whether the OIDC token is still valid — the vault-agent-stale detector is the
# stricter "needs re-login" signal we could point it at.
SPACESHIP_VAULT_SYMBOL_OK="${SPACESHIP_VAULT_SYMBOL_OK=}"    # U+F023 fa-lock (closed = secure)
SPACESHIP_VAULT_SYMBOL_BAD="${SPACESHIP_VAULT_SYMBOL_BAD=}"   # U+F09C fa-unlock (open = exposed)
SPACESHIP_VAULT_COLOR_OK="${SPACESHIP_VAULT_COLOR_OK=green}"          # named → the terminal theme's green
SPACESHIP_VAULT_COLOR_BAD="${SPACESHIP_VAULT_COLOR_BAD=red}"          # named → the terminal theme's red

spaceship_vault() {
  local ok=1
  if [[ "$OSTYPE" == darwin* ]]; then
    launchctl list rocks.stump.vault-agent >/dev/null 2>&1 || ok=0
  else
    systemctl --user is-active --quiet vault-agent 2>/dev/null || ok=0
  fi
  local sym col
  if (( ok )); then sym=$SPACESHIP_VAULT_SYMBOL_OK  col=$SPACESHIP_VAULT_COLOR_OK
  else              sym=$SPACESHIP_VAULT_SYMBOL_BAD col=$SPACESHIP_VAULT_COLOR_BAD; fi
  # --suffix supplies the trailing space; omitting it defaults to empty, which jams
  # the glyph against the next section (that was the "🔒in ~").
  spaceship::section \
    --color "$col" \
    --suffix "$SPACESHIP_PROMPT_DEFAULT_SUFFIX" \
    "$sym"
}

# ---- Right-side status dock -------------------------------------------------
# Single-icon, glanceable statuses live on the RIGHT prompt (right-adjusted on the top
# line) instead of cluttering the left. spaceship renders SPACESHIP_RPROMPT_ORDER on
# the right; setting it here (before the theme loads) beats spaceship's empty default.
#   vault  = the Vault Agent lock (always shown)
#   jobs   = background job count (only when > 0)
#   exit_code = ✘<code> of the last command (only when it failed)
#   battery   = charge indicator (only when low)
SPACESHIP_RPROMPT_ORDER=( vault jobs exit_code battery )
SPACESHIP_EXIT_CODE_SHOW="${SPACESHIP_EXIT_CODE_SHOW=true}"

# vault/battery/jobs/exit_code also sit in spaceship's default LEFT order — pull them
# off the left so they appear ONLY in the dock. Also add `kubectl_context` to the left
# (the default order carries `kubectl` = the version section, off by default — not the
# useful current-cluster/namespace one). spaceship fills its default order after
# $ZSH_CUSTOM loads, so mutate it from a cheap, idempotent precmd.
autoload -Uz add-zsh-hook
_spaceship_dock() {
  local s
  for s in vault battery jobs exit_code; do
    SPACESHIP_PROMPT_ORDER=("${(@)SPACESHIP_PROMPT_ORDER:#$s}")
  done
  if ! (( ${SPACESHIP_PROMPT_ORDER[(Ie)kubectl_context]} )); then
    local i=${SPACESHIP_PROMPT_ORDER[(Ie)host]}
    (( i )) && SPACESHIP_PROMPT_ORDER=( ${SPACESHIP_PROMPT_ORDER[1,i]} kubectl_context ${SPACESHIP_PROMPT_ORDER[i+1,-1]} )
  fi
}
add-zsh-hook precmd _spaceship_dock
