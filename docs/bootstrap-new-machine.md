# Bootstrapping a new machine

The whole environment comes up from **one command** on any machine that can reach
your Gitea. This is what makes the setup portable.

## One-liner

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

That command:

1. downloads and runs `chezmoi` (no prior install needed),
2. clones the private dotfiles repo into `~/.local/share/chezmoi`,
3. runs the `run_once_before_` bootstrap (below),
4. clones externals (themes + external plugins) per `.chezmoiexternal.toml`,
5. writes `~/.zshrc` and `~/.oh-my-zsh/custom/*`,
6. runs the `run_once_after_` hook wiring.

You'll be prompted once for Gitea credentials (HTTPS). On macOS they're cached in
the login keychain thereafter.

## From your laptop: `chezmoi ssh` (for ie01 / ie02)

`chezmoi ssh` (chezmoi ≥ 2.70) does the one-liner *for you over SSH*: it connects
to the host, installs chezmoi there, runs `chezmoi init --apply <repo>`, and drops
you into a shell on the box.

```sh
chezmoi ssh <host> https://gitea.stump.rocks/joestump/dotfiles.git
```

- **`<host>` must be SSH-reachable from your laptop** — the bare name `ie01` does
  not resolve here; use its real address: a Tailscale name, an FQDN
  (`ie01.stump.rocks`), or a `Host ie01` alias in `~/.ssh/config`.
- It runs the full bootstrap on the remote interactively, so the Ubuntu apt steps
  can prompt for `sudo`. Add `-p apt` if chezmoi can't auto-detect the package
  manager when installing itself.
- `-s=false` skips dropping into a shell afterward; `-- --one-shot <repo>` applies
  then removes chezmoi (ephemeral boxes — **not** what you want for ie01/ie02).

Equivalent to SSHing in yourself and running the one-liner — just fewer steps.

> **After it finishes**, secrets aren't loaded yet (that needs your identity):
> on the box, `vault login -method=oidc` (over SSH → use the tunnel; see
> [secrets.md](secrets.md#remote-machines--ssh)) then `vault-agent start`. That's
> when `~/.ssh/id_rsa` and the env secrets render on that machine.

## What the bootstrap does

`run_once_before_10-install-prereqs.sh` (before any file is written; idempotent):

- installs a package manager: **Homebrew** on macOS; on **Linux** it uses **apt only**
  (no Homebrew) for `zsh git curl ca-certificates gnupg`,
- on **Linux**, installs **Node 22** (NodeSource) so `qmd` has a modern runtime — a
  box with no node is detected gracefully and never aborts the bootstrap,
- installs **Oh My Zsh** if `~/.oh-my-zsh` is absent, using
  `RUNZSH=no KEEP_ZSHRC=yes` so it **never** overwrites the chezmoi-managed `~/.zshrc`.

Then chezmoi writes the files (including `~/.Brewfile`), and the **after** scripts run:

- `run_onchange_after_10-install-packages.sh` → `brew bundle --global` (the tool list),
  Go tools from `go-tools.txt`, and an OS-aware `vault` install. See
  [docs/packages.md](packages.md).
- `run_once_after_20-configure-git-hooks.sh` → sets `core.hooksPath=.githooks`
  (git clone doesn't carry it), wiring the gitleaks pre-commit hook.

## After first apply

1. **Set the terminal font** to a Nerd Font for the Spaceship/Powerlevel10k icons:
   ```sh
   brew install --cask font-meslo-lg-nerd-font
   ```
   then select it in your terminal profile.
2. **Authenticate OpenBao and start the Vault Agent** so secrets render:
   ```sh
   export VAULT_ADDR=https://vault.stump.rocks
   vault login -method=oidc      # seeds ~/.vault-token (the agent reads + renews it)
   vault-agent start             # launchd job renders ~/.config/vault/secrets-*.env
   ```
   (Static KV + the AWS engine already exist server-side — no re-setup.) See
   [docs/secrets.md](secrets.md).
3. Open a new shell (`exec zsh`).

## Updating an existing machine

```sh
chezmoi update                       # pull repo + apply
chezmoi apply --refresh-externals    # also re-pull theme/plugin upstreams
```

## What enables the portability (summary)

| Capability | Mechanism |
| --- | --- |
| One-command install | `chezmoi init --apply <repo>` |
| Install tools + OMZ on a bare machine | `run_once_before_` script |
| "My own OMZ ecosystem" (themes, external plugins) | `.chezmoiexternal.toml` git-repo externals |
| Reproducible repo-local git hooks | `run_once_after_` + `core.hooksPath` |
| Secrets that travel without being committed | OpenBao + Vault Agent (see [secrets.md](secrets.md)) |
