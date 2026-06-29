# Shell aliases & small shortcuts.

# reset — make it a FULL reset: reinitialize the terminal (the real `reset`), then
# run `czu` (chezmoi update + vault-agent restart + exec zsh) so config, secrets,
# the shell, AND the terminal all come back current. `command reset` calls the
# actual reset binary (no function recursion); `czu` is defined in chezmoi.zsh.
reset() {
  command reset "$@"
  [[ -o interactive ]] && czu
}
