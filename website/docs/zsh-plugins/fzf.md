---
title: fzf
---

# fzf

[fzf](https://github.com/junegunn/fzf) is the fuzzy finder; the OMZ plugin
locates the Homebrew install and wires up its key bindings and shell
completion. The binary comes from the Brewfile (`brew "fzf"`).

| Key | Does |
|---|---|
| **Ctrl+R** | fuzzy-search shell history, insert the pick |
| **Ctrl+T** | fuzzy-pick file(s), paste path(s) at the cursor |
| **Alt+C** | fuzzy-pick a directory and `cd` into it |
| `**<Tab>` | fuzzy completion for any command's argument |

## Pro tips

- **Ctrl+T mid-command** is the habit to build: type `vim `, hit Ctrl+T,
  fuzzy-type a fragment of the filename, Enter. Works for `git add`, `chezmoi
  edit`, anything. Multi-select with Tab inside the picker.
- **`**<Tab>`** triggers fzf completion where normal completion would run:
  `cd **<Tab>`, `kill -9 **<Tab>` (picks from a process list), `ssh **<Tab>`
  (picks from known hosts).
- If `FZF_DEFAULT_COMMAND` is unset, the plugin auto-prefers **`fd`, then
  `rg`, then `ag`** for file listing — respecting `.gitignore` and skipping
  `.git/`. `ripgrep` is one uncomment away in the Brewfile, and the
  `ZSH_AI_PROMPT_EXTEND` in `~/.zshrc` already tells zsh-ai to prefer rg/fd,
  so the tooling agrees with itself.
- **Ctrl+R beats blind ↑-mashing** for anything older than a few commands;
  for "I remember one word" cases, history-substring-search's ↑ is faster.
- Theme it to match Ghostty: export `FZF_DEFAULT_OPTS` with the
  [Catppuccin Mocha palette](https://github.com/catppuccin/fzf) so the picker
  stops looking like a ransom note against the Mocha background.
- The custom Tab binding (`autosuggest-tab.zsh`) defers to `fzf-completion`
  when no autosuggestion is showing, so `**<Tab>` keeps working.
