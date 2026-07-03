---
sidebar_position: 1
title: The Hub — macOS (required)
---

# Installing the Hub

This setup is a **hub-and-spoke model**. The hub — affectionately, *the
mothership* — is the machine you author from: dotfiles get edited and pushed
here, secrets get seeded here, and Linux spokes get provisioned *from* here
with one command ([`czinit`](nodes.md)).

:::warning The hub must be macOS
Parts of this stack depend on desktop apps that don't exist for Linux —
Claude Desktop and the macOS-side Signal pairing among them — and the hub
runs the launchd services (Vault Agent, signal-cli daemon) the rest of the
tooling assumes. Spokes can be Linux; the hub can't.
:::

## One command

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- \
  init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

This installs `chezmoi`, clones the repo, and runs the install end-to-end.

> **Installing this as your own?** Fork it and change one value —
> `githubUser` in `.chezmoidata.yaml` — and every repo URL, credential
> helper, and plugin source re-points to your handle. Secrets come from an
> OpenBao/Vault server at runtime (`VAULT_ADDR`), so point that at your own
> instance; nothing secret lives in this repo.

### What runs, in order

1. **`run_once_before_10-install-prereqs.sh`** — installs **Homebrew** (if missing)
   and **Oh My Zsh** (with `KEEP_ZSHRC=yes`, so it never clobbers the managed `.zshrc`).
2. **Files apply** — `~/.zshrc`, `~/.oh-my-zsh/custom/*.zsh`, `~/.Brewfile`, the
   Vault Agent config, the Ghostty config. Themes + external zsh plugins clone via
   chezmoi **externals**.
3. **`run_onchange_after_10-install-packages.sh`** — `brew bundle --global` (the
   tool list) + an OS-aware `vault` install + any Go tools.
4. **`run_onchange_after_*`** — Claude MCP merges, the plugin installs, the gitea hook.

## Finish the secrets handshake

The agent needs your identity once:

```bash
export VAULT_ADDR=https://vault.stump.rocks   # or your own OpenBao
vault login -method=oidc      # seeds ~/.vault-token; the agent renews it
vault-agent start             # launchd job renders ~/.config/vault/secrets-*.env
exec zsh
```

Now your API keys, AWS creds, and `~/.ssh/id_rsa` are all populated from OpenBao.
See [Secrets](../secrets) for the full picture.

## Make the prompt pretty

The prompt uses a Nerd Font. It's installed (`font-meslo-lg-nerd-font`); select it
in your terminal:

> **Ghostty / Terminal → Settings → Font → MesloLGS Nerd Font**

Ghostty itself is configured for you (Catppuccin Mocha, frosted glass) — see
[Terminal](../terminal).

## Daily loop

```bash
chezmoi edit ~/.zshrc          # edit the source
chezmoi apply                  # write it live
chezmoi cd && git add -A && git commit -m "…" && git push && exit
```

Spokes pull it with `chezmoi update`.
