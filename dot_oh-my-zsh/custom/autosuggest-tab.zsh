# Make <Tab> accept the grayed-out zsh-autosuggestion (from history) when one is
# showing; otherwise fall back to normal completion. The right-arrow / End keys
# still accept too — this just adds Tab.
#
# Loads from $ZSH_CUSTOM after the zsh-autosuggestions and fzf plugins, so it can
# defer to fzf's completion (preserving the `**<Tab>` fuzzy trigger) when there's
# no suggestion to accept.
_tab_accept_or_complete() {
  if [[ -n "$POSTDISPLAY" ]]; then
    # A suggestion is showing → accept it.
    zle autosuggest-accept
  elif (( $+widgets[fzf-completion] )); then
    # No suggestion, fzf present → use fzf-aware completion.
    zle fzf-completion
  else
    zle expand-or-complete
  fi
}
zle -N _tab_accept_or_complete
bindkey '^I' _tab_accept_or_complete   # ^I == Tab
