# Shell aliases & small shortcuts.

# reset — make it a FULL reset: reinitialize the terminal (the real `reset`) AND
# reload the shell, so both the display and the shell's env/config are a clean
# slate. `command reset` calls the actual reset binary (no function recursion).
reset() {
  command reset "$@"
  [[ -o interactive ]] && exec zsh
}
