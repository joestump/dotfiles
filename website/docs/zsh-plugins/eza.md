---
sidebar_position: 3
title: eza
---

# eza

[eza](https://github.com/eza-community/eza) is the maintained successor to
`exa` — a modern `ls` with colors, Nerd Font icons, git status, and tree view.
The OMZ plugin rebinds the `ls` family to it:

| Alias | Runs | Use for |
|---|---|---|
| `ls` | `eza --icons --group-directories-first` | everyday listing |
| `l` / `ll` | long view + git column | "what changed here?" inside a repo |
| `la` | long view incl. dotfiles | auditing a directory fully |
| `tree` | `eza --tree` | replaces the `tree` binary entirely |

The binary comes from the Brewfile (`brew "eza"`); the plugin config lives as
`zstyle ':omz:plugins:eza' …` lines in `dot_zshrc` (icons, git-status,
dirs-first are on).

## Pro tips

- **`ll` inside any git repo** shows a per-file git column (`M`, `N`, `I`) — a
  free micro-`git status` on every listing.
- **`tree -L 2`-style depth** works as `eza --tree --level=2`. Alias-worthy if
  you use it a lot.
- **Sort by recency**: `eza -l --sort=modified --reverse` puts the newest files
  on top — the "what did I just download" command.
- The `ZSH_AI_PROMPT_EXTEND` in `~/.zshrc` already tells zsh-ai to prefer eza,
  so `#`-generated commands and your actual aliases now agree.
- Icons render as tofu boxes if the terminal font isn't a Nerd Font — Ghostty
  is already set to MesloLGS NF, so this only bites in other terminals.
