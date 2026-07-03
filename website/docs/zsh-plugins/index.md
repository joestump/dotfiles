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

Every plugin has its own pro-tips page — the table links them all.

| Group | Plugins |
|---|---|
| Git & forges | [`git`](git.md), [`git-auto-fetch`](git-auto-fetch.md), [`gh`](gh.md), [`shlink`](shlink.md) |
| Containers & cloud | [`docker`](docker.md), [`docker-compose`](docker-compose.md), [`aws`](aws.md), [`terraform`](terraform.md), [`kubectl`](kubectl.md), [`kubectx`](kubectx.md), [`helm`](helm.md) |
| Languages & packages | [`brew`](brew.md), [`macos`](macos.md), [`python`](python.md), [`pip`](pip.md), [`virtualenv`](virtualenv.md), [`npm`](npm.md) |
| Navigation & files | [`zoxide`](zoxide.md), [`eza`](eza.md), [`dirhistory`](dirhistory.md), [`copypath`](copypath.md), [`copyfile`](copyfile.md), [`extract`](extract.md) |
| History & typing | [`zsh-autosuggestions`](zsh-autosuggestions.md), [`history-substring-search`](history-substring-search.md), [`fzf`](fzf.md), [`sudo`](sudo.md), [`alias-finder`](alias-finder.md), [`zsh-ai`](zsh-ai.md) |
| Data & display | [`jsontools`](jsontools.md), [`urltools`](urltools.md), [`zsh-syntax-highlighting`](zsh-syntax-highlighting.md), [`colored-man-pages`](colored-man-pages.md), [`colorize`](colorize.md) |

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

Each page keeps to the pro tips worth actually remembering — the aliases and
keybinds that earn their muscle memory, aimed at how this setup is actually
used (Compose-based StumpCloud ops, Gitea + GitHub, OpenBao secrets, the
Docusaurus site, and a lot of Claude).
