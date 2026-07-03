---
sidebar_position: 1
title: Zsh Plugins
---

# Zsh Plugins

The Oh My Zsh plugin roster lives in one place — the `plugins=(...)` array in
`~/.zshrc` (source: `dot_zshrc`). Everything here is either bundled with OMZ or
cloned automatically via chezmoi externals (`.chezmoiexternal.toml`), so a fresh
machine gets the identical set from `chezmoi apply`.

## The full roster

| Group | Plugins |
|---|---|
| Git & forges | `git`, `git-auto-fetch`, `gh` |
| Cloud & infra | `aws`, `terraform`, `kubectl`, `kubectx`, `helm`, `docker`, `docker-compose` |
| Languages & packages | `brew`, `python`, `pip`, `virtualenv`, `npm` |
| Navigation & files | `zoxide`, `dirhistory`, [`eza`](eza.md), [`copypath`](copypath.md), [`copyfile`](copyfile.md), `extract` |
| History & typing | `zsh-autosuggestions`, [`history-substring-search`](history-substring-search.md), [`sudo`](sudo.md), [`alias-finder`](alias-finder.md) |
| Data munging | `jsontools`, [`urltools`](urltools.md) |
| Eye candy & safety | `colored-man-pages`, `colorize`, `zsh-syntax-highlighting` |
| Search | `fzf` |
| Mine / external | `shlink`, `zsh-ai`, `macos` |

**Load-order rules** (encoded as comments in `dot_zshrc` — don't reorder casually):

1. `zsh-syntax-highlighting` loads last of the "normal" plugins.
2. `history-substring-search` is the one exception — its README requires it to
   load *after* syntax-highlighting, so it holds the final slot.

## Deliberately not installed

| Plugin | Why not |
|---|---|
| `z` | `zoxide` is already enabled and strictly better (frecency + `zi` interactive picker). |
| `thefuck` | Unmaintained upstream; `zsh-ai` (`# fix that` + Enter) covers the use case. |
| `zsh-autocomplete` | Fights `zsh-autosuggestions` and the custom `autosuggest-tab.zsh` Tab binding. |
| `fast-syntax-highlighting` | Drop-in for zsh-syntax-highlighting, but the zdharma repo-deletion history makes it a risky dependency for marginal gain. |
| `1password` | Secrets come from OpenBao via Vault Agent, not 1Password. |
| `web-search` | `zsh-ai` answers from the terminal already. |
| `command-not-found` | On macOS it needs the `homebrew-command-not-found` tap; this repo deliberately avoids tap-trust friction. |

The pages in this section cover the plugins added in the July 2026 review, each
with the pro tips worth actually remembering.
