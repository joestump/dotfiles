# Argument completion for the Claude Code CLI (`claude`).
#
# claude ships no completion script and self-updates often, so rather than hard-code
# a flag list that rots, this GENERATES the flags + subcommands from `claude --help`
# and caches them. The cache is keyed on the *resolved* binary path
# (~/.local/bin/claude is a symlink into versions/<ver>), so when claude updates the
# key changes and the cache rebuilds automatically. Identical on macOS and Linux.
_claude() {
  emulate -L zsh
  local bin
  bin=$(command -v claude 2>/dev/null) || return 1
  bin=${bin:A}                                       # resolve symlink → versioned path
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-completion.zsh"

  # (Re)build the cache when it's missing or the resolved binary changed (update).
  if [[ ! -s $cache || "${$(head -n1 -- $cache 2>/dev/null)#\# }" != "$bin" ]]; then
    mkdir -p -- "${cache:h}" 2>/dev/null
    local help; help=$("$bin" --help 2>/dev/null)
    {
      print -r -- "# $bin"
      printf '_claude_flags=( %s )\n' \
        "$(print -r -- "$help" | grep -oE -- '--[a-z][a-z0-9-]+' | sort -u | tr '\n' ' ')"
      printf '_claude_cmds=( %s )\n' \
        "$(print -r -- "$help" | sed -n '/^Commands:/,$p' | grep -E '^  [a-z]' \
            | awk '{sub(/\|.*/,"",$1); print $1}' | sort -u | tr '\n' ' ')"
    } >| "$cache" 2>/dev/null
  fi

  local -a _claude_flags _claude_cmds
  source "$cache" 2>/dev/null

  # Has a subcommand already been chosen on the line?
  local seen= w
  for w in ${words[2,CURRENT-1]}; do
    if (( ${_claude_cmds[(Ie)$w]} )); then seen=$w; break; fi
  done

  if [[ ${words[CURRENT]} == -* ]]; then
    compadd -a _claude_flags                         # completing a flag
  elif [[ -z $seen ]]; then
    _describe -t commands 'claude command' _claude_cmds && compadd -a _claude_flags
  else
    compadd -a _claude_flags                          # inside a subcommand: flags + files
    _files
  fi
}
(( $+functions[compdef] )) && compdef _claude claude
