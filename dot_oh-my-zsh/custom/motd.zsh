# motd.zsh — StumpCloud login banner, themed to the pink spaceship prompt
# (Catppuccin Mocha). Dynamic facts. Auto-shows on interactive LOGIN shells (new
# terminals / SSH sessions) — not every subshell. Run `motd` anytime;
# `export NO_MOTD=1` to silence the auto-display.

motd() {
  emulate -L zsh
  local p=$'\e[38;5;213m'  m=$'\e[38;5;177m'  c=$'\e[38;5;117m'
  local g=$'\e[38;5;150m'  y=$'\e[38;5;223m'  d=$'\e[38;5;244m'
  local b=$'\e[1m'  r=$'\e[0m'

  # a cute glyph from the same pool as the prompt
  local -a gl=( "${PROMPT_GLYPHS[@]}" ); (( ${#gl} )) || gl=( '*' '+' 'o' )
  local q=${gl[$((RANDOM % ${#gl} + 1))]}

  # --- cloud ---
  print -r -- ""
  print -r -- "${y}          ⋆ ${p}${q}${y} ﹒ ⋆${r}"
  print -r -- "${c}        .--.      .--.${r}"
  print -r -- "${c}     .-(    ).--.(    )-.${r}"
  print -r -- "${c}    (___.__)____(__.___)${r}"

  # --- wordmark: gradient figlet, with a hardcoded fallback ---
  local -a grad=( 213 212 211 177 141 105 ); local i=1 line
  if command -v figlet >/dev/null 2>&1; then
    { figlet -f slant 'StumpCloud' 2>/dev/null || figlet 'StumpCloud' 2>/dev/null; } |
      while IFS= read -r line; do
        print -r -- $'\e[1;38;5;'"${grad[$(((i-1)%${#grad}+1))]}"$'m'"${line}"$'\e[0m'
        (( i++ ))
      done
  else
    print -r -- ""
    print -r -- "${b}${p}   ▄▖▗ ▖ ▖▎▖▖▄▖ ${m}▄▖▖ ▄▖▖▖▄▖${r}"
    print -r -- "${b}${p}   ▚ ▜ ▌▌▌▎▌▌▙▌ ${m}▌ ▌ ▌▌▌▌▌▌${r}"
    print -r -- "${b}${p}   ▄▌▐ ▙▌▌▎▙▌▌  ${m}▙▖▙▖▙▌▙▌▙▌${r}"
  fi

  # --- dynamic facts ---
  local host kern os up load disk now
  host="$(hostname -s 2>/dev/null || hostname)"
  kern="$(uname -r)"
  now="$(date '+%a %d %b · %H:%M')"
  if [[ "$OSTYPE" == darwin* ]]; then
    os="macOS $(sw_vers -productVersion 2>/dev/null)"
    up="$(uptime | sed -E 's/^.*up[[:space:]]+//; s/,[[:space:]]+[0-9]+ users?.*//; s/,[[:space:]]+load.*//')"
    load="$(uptime | sed -E 's/^.*averages?:[[:space:]]*//')"
  else
    os="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}" )"
    up="$(uptime -p 2>/dev/null | sed 's/^up //')"
    load="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
  fi
  disk="$(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"}')"

  local fmt="  ${c}%-7s${r} %s"
  print -r -- ""
  print -r -- "  ${p}${q}${r}  ${g}${USER}${d}@${r}${b}${p}${host}${r}    ${d}${now}${r}"
  printf "$fmt\n" "os"     "$os"
  printf "$fmt\n" "kernel" "$kern"
  printf "$fmt\n" "uptime" "${up:-?}"
  printf "$fmt\n" "load"   "${load:-?}"
  printf "$fmt\n" "disk"   "${disk:-?}"
  print -r -- ""
}

# Show on interactive LOGIN shells only (new terminal / SSH), unless silenced.
[[ -z ${NO_MOTD:-} && -o interactive && -o login ]] && motd
