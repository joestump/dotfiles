---
sidebar_position: 1
title: The Hub — macOS (required)
---

# Installing the Hub

This setup is a **hub-and-spoke model**. The hub — affectionately, *the
mothership* — is the machine you author from: dotfiles get edited and pushed
here, secrets get seeded here, and Linux spokes get provisioned *from* here
with one command ([`czinit`](nodes.md)).

:::warning[The hub must be macOS]
Parts of this stack depend on desktop apps that don't exist for Linux —
Claude Desktop and the macOS-side Signal pairing among them — and the hub
runs the launchd services (Vault Agent, signal-cli daemon, the harness daemon)
the rest of the tooling assumes. Spokes can be Linux; the hub can't.
:::

## One command

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

This installs `chezmoi`, clones the repo into chezmoi's **default source dir**
(`~/.local/share/chezmoi`), and runs the install end-to-end.

:::danger[Don't pass `--source`]
A bare `init` is deliberate. `--source ~/src/dotfiles` used to be required here,
back when the config pinned `sourceDir` to that path — and it is now actively
wrong. The rendered `chezmoi.toml` sets no `sourceDir`, so a bare init leaves the
config and the clone agreeing; passing `--source` leaves them pointing at
different places, and chezmoi has been known to respond to that by proposing to
delete the entire home directory.

`~/.local/share/chezmoi` is the **production** clone. `~/src/dotfiles` is a
separate development **workbench** that only exists on machines where someone
develops — see [Editing](../workflow).
:::

> **Installing this as your own?** Fork it and change one value —
> `githubUser` in `.chezmoidata.yaml` — and every repo URL, credential
> helper, and plugin source re-points to your handle. Secrets come from an
> OpenBao/Vault server at runtime (`VAULT_ADDR`), so point that at your own
> instance; nothing secret lives in this repo.

### What runs, in order

1. **`run_once_before_10-install-prereqs.sh`** — installs **Homebrew** (if missing)
   and **Oh My Zsh** (with `KEEP_ZSHRC=yes`, so it never clobbers the managed `.zshrc`).
2. **Files apply** — `~/.zshrc`, `~/.oh-my-zsh/custom/*.zsh`, `~/.Brewfile`, the
   Vault Agent config, the Ghostty config, the harness and Crush configs, the
   composed agent rules. Themes + external zsh plugins clone via chezmoi
   **externals**.
3. **`run_onchange_after_10-install-packages.sh`** — `brew bundle --global` (the
   tool list) + an OS-aware `vault` install + the Go tools.
4. **`run_after_3x`** — builds Crush and the harness daemon from source, installs
   the Claude plugins and msgbrowse, sets up the Signal MCP venv and Ansible.
5. **`run_after_4x` / `run_onchange_after_4x–5x`** — the Claude MCP merges for both
   apps, the service definitions (Vault Agent, signal daemon, harness daemon), the
   scheduled `czu` and qmd timers, and the terminfo entry.

## Finish the secrets handshake

The agent needs an identity once:

```bash
export VAULT_ADDR=https://vault.stump.rocks   # or your own OpenBao
vault-oidc-login              # OIDC login; seeds ~/.vault-token
czapprole --local             # provision this box's self-renewing AppRole
vault-agent restart           # render ~/.config/vault/secrets-*.env now
exec zsh
```

`czapprole --local` is the step that matters: it gives the agent a **machine
identity** so it renews itself forever, instead of dying when an interactive OIDC
token hits its max TTL. Now your API keys, AWS credentials, `~/.netrc` and
`~/.ssh/id_rsa` are all populated from OpenBao. See [Secrets](../secrets) for the
full picture.

## Make the prompt pretty

The prompt uses a Nerd Font. It's installed (`font-meslo-lg-nerd-font`); select it
in your terminal:

> **Ghostty / Terminal → Settings → Font → MesloLGS Nerd Font**

Ghostty itself is configured for you (Catppuccin Mocha, frosted glass) — see
[Terminal](../terminal).

## Daily loop

Once the box is up, keeping it current is one command:

```bash
czu                       # sync + apply + re-render secrets + reload the shell
```

Changing something is a different loop, and it happens in the **workbench**, not
in the live files:

```bash
cd ~/src/dotfiles && git switch -c feat/thing origin/main
$EDITOR dot_zshrc                                        # edit the SOURCE
chezmoi apply --source ~/src/dotfiles ~/.zshrc           # try it before merging
bats test/ && git commit -am "feat: thing" && git push   # PR → merge
```

Every box — including this one — picks it up on its next `czu`. Full detail:
[Editing](../workflow).
