---
sidebar_position: 1
title: The Mothership (macOS)
---

# Bootstrapping the Mothership

The mothership is the macOS laptop — the machine I author from. It gets the full
stack: Homebrew, Oh My Zsh, the Vault Agent, SSH keys, Claude config.

## One command

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- \
  init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

This installs `chezmoi`, clones the private repo, and runs the bootstrap end-to-end.
You'll be prompted **once** for Gitea credentials (HTTPS) — cached in the login
keychain after that.

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
export VAULT_ADDR=https://vault.stump.rocks
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

Other machines pull it with `chezmoi update`.
