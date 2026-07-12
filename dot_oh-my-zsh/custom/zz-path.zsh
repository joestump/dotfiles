# zz-path.zsh — runs absolutely last in OMZ custom files.
# Ensures that user-local bins (~/.local/bin and ~/bin) are placed at the absolute
# front of the PATH, properly shadowing any system-wide or Homebrew defaults.
typeset -U path PATH
path=( "$HOME/.local/bin" "$HOME/bin" $path )
