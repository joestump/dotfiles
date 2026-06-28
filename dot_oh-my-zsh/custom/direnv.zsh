# Hook direnv into zsh. Lives in $ZSH_CUSTOM so Oh My Zsh auto-sources it
# after oh-my-zsh.sh — no edit to ~/.zshrc required.
# Guarded so a missing direnv (e.g. fresh machine before `brew install`) does
# not break shell startup.
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
