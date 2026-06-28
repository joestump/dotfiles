---
sidebar_position: 1
title: Overview
slug: /overview
---

# How it all works

These dotfiles turn a fresh machine into **my** machine with one command. Everything
is declarative, backed by self-hosted infrastructure, and the same on every box.

```
        ┌──────────────────────────── chezmoi ────────────────────────────┐
        │  gitea.stump.rocks/joestump/dotfiles  (private, the source)      │
        └───────────────┬───────────────────────────────┬─────────────────┘
                        │ chezmoi init --apply           │
              ┌─────────▼─────────┐             ┌─────────▼──────────┐
              │   MOTHERSHIP      │             │   UTILITY NODES    │
              │   macOS laptop    │             │   ie01, ie02, …    │
              │   Homebrew        │             │   Ubuntu / apt     │
              └─────────┬─────────┘             └─────────┬──────────┘
                        │  Oh My Zsh + helpers + tooling   │
                        └───────────────┬──────────────────┘
                              ┌─────────▼─────────┐
                              │  OpenBao + Vault  │  secrets, never in the repo
                              │  Agent → env/files│
                              └───────────────────┘
```

## The pieces

| Layer | Tool | What it does |
| --- | --- | --- |
| **Dotfile management** | [chezmoi](https://chezmoi.io) | Source of truth at `~/.local/share/chezmoi`, pushed to Gitea. Renders `~/.zshrc` + `~/.oh-my-zsh/custom/` and a few configs. |
| **Shell** | Oh My Zsh | Curated plugins, helper functions auto-loaded from `$ZSH_CUSTOM`, spaceship prompt. |
| **Secrets** | OpenBao + Vault Agent | A launchd agent renders every `secret/personal/*` to env files + SSH keys on a schedule. Nothing secret is committed. |
| **Packages** | Homebrew (macOS) / apt (Linux) | A `Brewfile` and an apt list, installed by `run_onchange_` scripts. |
| **AI tooling** | Claude Code + Desktop | MCP servers and plugins managed declaratively (shared list, OpenBao-sourced tokens). |
| **CI / this site** | Gitea Actions + Garage Pages | BATS + lint on every push; this site builds and ships to Garage S3. |

## Two kinds of machine

- **The Mothership** — my macOS laptop. Full setup: Homebrew, the Vault Agent, SSH
  keys, Claude config, the works. → [Bootstrap the Mothership](bootstrap/mothership).
- **Utility Nodes** — Linux boxes I spin up and tear down (`ie01`, `ie02`, …). Lean,
  apt-based, **no Homebrew**. → [Bootstrap a Node](bootstrap/nodes).

## The golden rule

> Edit the **source**, not the live files. `chezmoi edit ~/.zshrc` (not `~/.zshrc`
> directly), commit, push. Pull anywhere with `chezmoi update`.

Secrets are the one thing that never lives in the repo — they come from
[OpenBao at runtime](secrets). Everything else is reproducible from `git`.
