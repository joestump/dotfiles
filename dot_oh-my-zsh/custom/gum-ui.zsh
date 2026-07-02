# gum-ui.zsh — shared theming + guards for the gum-powered helpers (dot/theme/status,
# and the czu/czinit banners). gum is the charm TUI toolkit (brew/apt: gum).
#
# Everything that uses gum guards on `_have gum` and, for interactive widgets, on a
# TTY — so a fresh node (gum not yet installed) or a non-interactive context (cron,
# ssh -o BatchMode, a chezmoi script) degrades gracefully instead of hanging/erroring.

# _have <cmd> — true if the command exists. Tiny shared helper.
_have() { command -v "$1" >/dev/null 2>&1 }

# Theme gum to match the pink spaceship prompt / StumpCloud MOTD (Catppuccin-ish
# 256-color palette: pink 213, mauve 177, sky 117, green 150, yellow 223). gum reads
# these GUM_<COMMAND>_<OPTION> env vars; flags still override per-call.
if _have gum; then
  export GUM_CHOOSE_CURSOR_FOREGROUND=213
  export GUM_CHOOSE_HEADER_FOREGROUND=117
  export GUM_CHOOSE_SELECTED_FOREGROUND=177
  export GUM_FILTER_INDICATOR_FOREGROUND=213
  export GUM_FILTER_MATCH_FOREGROUND=213
  export GUM_FILTER_PROMPT_FOREGROUND=117
  export GUM_CONFIRM_SELECTED_BACKGROUND=213
  export GUM_CONFIRM_PROMPT_FOREGROUND=117
  export GUM_INPUT_CURSOR_FOREGROUND=213
  export GUM_INPUT_PROMPT_FOREGROUND=117
  export GUM_SPIN_SPINNER=minidot
  export GUM_SPIN_TITLE_FOREGROUND=117
fi
