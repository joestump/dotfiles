---
sidebar_position: 5
title: Terminal & Prompt
---

# Terminal & Prompt

![The `dot` action hub and the `status` health panel — gum-powered TUI helpers](/img/screenshots/menus.png)

## Prompt — spaceship

Two-line spaceship prompt with the hostname always shown (so you know which box
you're on), no leading blank line, and a **random cute Nerd Font glyph** as the
prompt character — re-rolled every shell, in pink.

The glyph pool is a variable in `~/.zshrc` you can curate:

```zsh
PROMPT_GLYPHS=(
  $''   # zap
  $''   # star
  $''   # heart
  $''   # paw
  $''   # rocket
  $''   # coffee
)
```

`~/.oh-my-zsh/custom/spaceship.zsh` picks one at random. Swap the theme by changing
`ZSH_THEME` (spaceship, powerlevel10k, quantum, comfyline are all installed via
chezmoi externals).

## Plugins

Curated OMZ set — `git`, `gh`, `aws`, `kubectl`, `docker`, `colorize`,
`git-auto-fetch`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, plus
`zsh-ai` (type `# describe a command` + Enter) and quality-of-life picks like
`history-substring-search`, `eza`, `sudo`, and `alias-finder`. External plugins
clone via chezmoi externals. `Tab` accepts the autosuggestion.

Full roster, load-order rules, and per-plugin pro tips: [Zsh Plugins](zsh-plugins/index.md).

## Ghostty

The terminal config (`~/.config/ghostty/config`) is managed too — MesloLGS Nerd
Font, **Catppuccin Mocha**, a blinking bar cursor, frosted-glass background, native
tabs, Option-as-Alt, copy-on-select. Reload in-app with **⌘⇧,**.

> The fonts render via a Nerd Font — set your terminal font to **MesloLGS Nerd
> Font** or the glyphs show as tofu boxes.
