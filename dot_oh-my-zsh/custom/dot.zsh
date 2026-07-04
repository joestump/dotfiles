# dot / theme / status — the fun, gum-powered dotfiles helpers.
#   dot     — an interactive action hub (the front door)
#   theme   — switch the zsh prompt theme, persisted per-machine
#   status  — a quick health panel for the StumpCloud stack
# All need gum (see gum-ui.zsh); the interactive ones also need a TTY. They degrade
# with a clear message rather than hanging when either is missing.

# theme — pick a prompt theme. The choice is written to a per-machine override file
# (~/.config/dotfiles/zsh-theme, NOT chezmoi-managed) that ~/.zshrc reads before it
# loads Oh My Zsh — so it survives `chezmoi apply` and can differ per box.
theme() {
  emulate -L zsh
  _have gum || { print -u2 "theme: needs gum (brew install gum / apt install gum)"; return 1 }
  [[ -t 0 && -t 1 ]] || { print -u2 "theme: needs an interactive terminal"; return 1 }
  local -a themes=(
    spaceship-prompt/spaceship
    powerlevel10k/powerlevel10k
    quantum-zsh/quantum
    comfyline_prompt/comfyline
    robbyrussell
  )
  local pick
  pick=$(printf '%s\n' "${themes[@]}" | gum choose --header "prompt theme  (now: ${ZSH_THEME})") || return
  [[ -n "$pick" ]] || return
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/zsh-theme"
  mkdir -p "${f:h}"; print -r -- "$pick" >| "$f"
  gum style --foreground 150 "✓ theme → ${pick}    reloading…"
  exec zsh
}

# _skills_freshness — read ~/.config/dotfiles/claude-plugins.tsv, compare each
# local-path marketplace's current git HEAD against its installed sentinel (written
# by run_after_install-claude-plugins.sh.tmpl), and print "<fresh>/<total>". Remote
# marketplaces (GitHub) can't be freshness-checked without a network fetch, so they
# count as fresh here — the install script handles them with `claude plugin update`.
_skills_freshness() {
  emulate -L zsh
  local list="$HOME/.config/dotfiles/claude-plugins.tsv"
  local state="$HOME/.config/dotfiles/.claude-plugin-state"
  [[ -r "$list" ]] || { print -r -- "?"; return }
  local total=0 fresh=0 line src plugin sentinel head
  local -a fields
  while IFS= read -r line; do
    [[ -z "${line// }" || "$line" == \#* ]] && continue
    fields=( ${=line} )
    (( ${#fields} >= 2 )) || continue
    src="${fields[1]/#\~/$HOME}"
    plugin="${fields[2]}"
    (( total++ ))
    sentinel="$state/${plugin//[^A-Za-z0-9_.@-]/_}"
    if [[ -d "$src/.git" ]]; then
      head=$(git -C "$src" rev-parse HEAD 2>/dev/null)
      [[ -n "$head" && "$head" == "$(<$sentinel 2>/dev/null)" ]] && (( fresh++ ))
    else
      (( fresh++ ))
    fi
  done < "$list"
  print -r -- "${fresh}/${total} fresh"
}

# status — health panel: vault-agent, signal-cli daemon, dotfiles drift, Claude
# skill marketplaces, disk. Each row gets a service-specific glyph so the panel
# scans as a legend, not five identical bullets. Color still carries state.
status() {
  emulate -L zsh
  _have gum || { print -u2 "status: needs gum"; return 1 }
  local host="${HOST%%.*}" va sd df disk pend skills sk_color
  if [[ "$OSTYPE" == darwin* ]]; then
    launchctl list 2>/dev/null | grep -q 'rocks\.stump\.vault-agent' && va=up || va=down
  else
    systemctl --user is-active --quiet vault-agent 2>/dev/null && va=up || va=down
  fi
  nc -z 127.0.0.1 7583 2>/dev/null && sd=up || sd=down
  pend=$(chezmoi status 2>/dev/null | grep -c . | tr -d ' ')
  { [[ -z "$pend" || "$pend" == 0 ]] && df=clean } || df="${pend} pending"
  skills=$(_skills_freshness)
  disk=$(df -h / 2>/dev/null | awk 'NR==2{print $5" used"}')

  local ok=150 bad=210 hl=213 warn=223 dim=244
  if [[ "$skills" == "?" ]]; then
    sk_color=$dim
  elif [[ "$skills" =~ ^([0-9]+)/([0-9]+) ]] && (( match[1] == match[2] )); then
    sk_color=$ok
  else
    sk_color=$warn
  fi
  gum style --foreground "$hl" --bold "📊 status · ${host}"
  gum join --vertical \
    "$(gum style --foreground $([[ $va == up ]] && print $ok || print $bad) "  🔐 vault-agent    ${va}")" \
    "$(gum style --foreground $([[ $sd == up ]] && print $ok || print $bad) "  📡 signal-daemon  ${sd}")" \
    "$(gum style --foreground $([[ $df == clean ]] && print $ok || print $warn) "  📥 dotfiles       ${df}")" \
    "$(gum style --foreground "$sk_color" "  🔌 skills         ${skills}")" \
    "$(gum style --foreground $dim "  💾 disk           ${disk:-?}")"
}

# dot — the action hub. One friendly front door to the common chores. Each label
# leads with a themed glyph so the menu reads as a dashboard; case matching is on
# the significant word, not the emoji, so relabelling is cheap.
dot() {
  emulate -L zsh
  _have gum || { print -u2 "dot: needs gum (brew install gum / apt install gum)"; return 1 }
  [[ -t 0 && -t 1 ]] || { print -u2 "dot: needs an interactive terminal"; return 1 }
  local choice
  choice=$(gum choose --header "⚡ dotfiles · action" \
    "🔄 Update everything (czu)" \
    "🎨 Switch theme" \
    "📊 Status dashboard" \
    "📱 Link Signal device" \
    "🔁 Restart a daemon" \
    "✏️  Edit a config" \
    "📖 Open the docs") || return
  case "$choice" in
    *Update*)  czu ;;
    *theme*)   theme ;;
    *Status*)  status ;;
    *Link*)    _have signal-link && signal-link || print -u2 "signal-link unavailable here" ;;
    *Restart*) local d; d=$(gum choose vault-agent signal-daemon) || return; [[ -n "$d" ]] && "$d" restart ;;
    *Edit*)    local rel; rel=$(chezmoi managed --include=files 2>/dev/null | gum filter --placeholder "config to edit…") || return
               [[ -n "$rel" ]] && chezmoi edit "$HOME/$rel" ;;
    *Open*)    local u="https://joestump.pages.stump.rocks/dotfiles/"
               if _have open; then open "$u"; elif _have xdg-open; then xdg-open "$u" >/dev/null 2>&1; else print -r -- "$u"; fi ;;
  esac
}
