---
sidebar_position: 7
title: Architecture
---

# Architecture & decisions

The design rationale, distilled.

## Separation of concerns (the core constraint)

| Kind | Lives in | Never |
| --- | --- | --- |
| Shell helpers | one `*.zsh` per file in `~/.oh-my-zsh/custom/` (OMZ auto-sources) | — |
| Non-secret config | direnv `.envrc` per project | — |
| Secrets | OpenBao, rendered at runtime by the Vault Agent | in a file, `.env`, or the repo |

## Key decisions

- **chezmoi manages only** `~/.zshrc`, `~/.oh-my-zsh/custom/`, and a few configs
  (`~/.Brewfile`, `~/.config/{vault,ghostty,dotfiles}`). OMZ self-updates the rest
  of its tree, guarded by `.chezmoiignore` (`.oh-my-zsh/*` + `!.oh-my-zsh/custom/`).
- **HTTPS + osxkeychain** for the Gitea remote (no SSH-key wiring on the mothership).
- **`run_onchange_` + manifest hashes** so package/MCP/plugin installs re-run only
  when their list changes.
- **`.chezmoiscripts/`** for installs that aren't files; **externals** for cloned
  upstreams (themes, plugins, the private skills marketplace).
- **Secrets are OpenBao-authoritative**; the agent renders them so machines stay
  disposable — re-image a node, `vault login`, and you're whole again.
- **vault, not bao** — the Homebrew `bao` is the BLAKE3 tool, a trap worth a warning.

## Repo layout

```
dot_zshrc                          → ~/.zshrc
dot_oh-my-zsh/custom/*.zsh         → helpers, prompt, secrets loader
dot_Brewfile                       → ~/.Brewfile
dot_config/dotfiles/               → Brewfile-adjacent manifests (apt, go, mcp, plugins)
dot_config/vault/                  → Vault Agent config + Consul-Templates
.chezmoiscripts/                   → run_onchange_ installers (packages, claude, …)
.chezmoiexternal.toml              → cloned themes, plugins, marketplaces
.githooks/  .gitleaks.toml         → secret-leak prevention
test/  .gitea/workflows/ci.yml     → BATS + lint CI
website/                           → this Docusaurus site
```

The repo is the canonical record — the `Architecture.md` in it goes deeper, and the
[Gitea repo](https://gitea.stump.rocks/joestump/dotfiles) is the source of truth.
