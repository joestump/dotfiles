# dotfiles

Personal dotfiles, managed with [chezmoi](https://www.chezmoi.io/), backed by
self-hosted Gitea at <https://gitea.stump.rocks/joestump/dotfiles> (private), and
layered on an existing [Oh My Zsh](https://ohmyz.sh/) install.

chezmoi manages **only** `~/.zshrc` and `~/.oh-my-zsh/custom/`. Oh My Zsh
self-updates the rest of its tree and is never touched by chezmoi.

## Docs

- **[docs/usage.md](docs/usage.md)** — day-to-day: add helpers, swap themes, plugins, direnv.
- **[docs/packages.md](docs/packages.md)** — declarative tooling (Brewfile, Go tools) on macOS + Ubuntu.
- **[docs/secrets.md](docs/secrets.md)** — OpenBao + Vault Agent: how secrets reach your shell.
- **[docs/bootstrap-new-machine.md](docs/bootstrap-new-machine.md)** — one-command setup on any machine.
- **[Architecture.md](Architecture.md)** — design rationale and decisions.

## Set up on a new machine (one command)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

Installs Homebrew + tools + Oh My Zsh, clones themes/plugins, and applies
everything. To bootstrap a **remote** box (ie01/ie02) from your laptop in one
step: `chezmoi ssh <host> https://gitea.stump.rocks/joestump/dotfiles.git`.
See [docs/bootstrap-new-machine.md](docs/bootstrap-new-machine.md).

## Separation of concerns

| Kind | Where it lives | Example |
| --- | --- | --- |
| Shell helper functions | one `*.zsh` per helper in `~/.oh-my-zsh/custom/` (OMZ auto-sources) | `dot_oh-my-zsh/custom/vault-login.zsh` |
| Non-secret config | direnv `.envrc` per project | [`examples/envrc.example`](examples/envrc.example) |
| Secrets | **never** in files or this repo — held in OpenBao (<https://vault.stump.rocks>); a Vault Agent renders them on a schedule and OMZ sources the result | [docs/secrets.md](docs/secrets.md) |

No dotenvx. No `python-dotenv`. No committed `.env`. A `gitleaks` pre-commit hook
blocks accidental secret commits.

## What's in here

```
dot_zshrc                          → ~/.zshrc  (theme + plugins; seeded from OMZ)
dot_oh-my-zsh/custom/*.zsh         → ~/.oh-my-zsh/custom/  (helpers + secrets loader)
dot_Brewfile                       → ~/.Brewfile  (declarative tooling; brew bundle)
dot_config/dotfiles/go-tools.txt   → Go tools to `go install`
dot_config/vault/                  → Vault Agent config + Consul-Templates
.chezmoiexternal.toml              → clones themes + external plugins on apply
run_once_before_*.sh               → bootstrap: Homebrew + Oh My Zsh (+ apt prereqs on Linux)
run_once_after_*.sh                → brew bundle + Go tools + vault; wire the gitleaks hook
.chezmoiignore                     → keep chezmoi to .zshrc + custom/ (+ a few managed files)
.githooks/  .gitleaks.toml         → secret-leak prevention
examples/  docs/  scripts/  test/  → repo-only (not applied to $HOME)
```

### Themes (swap via `ZSH_THEME` in `~/.zshrc`)

`spaceship-prompt/spaceship` (default) · `powerlevel10k/powerlevel10k` ·
`quantum-zsh/quantum`. Installed as externals — see
[docs/usage.md](docs/usage.md#swap-the-prompt-theme).

## Add a helper (quick reference)

```sh
$EDITOR ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi cd && git add -A && git commit -m "Add my-helper" && git push && exit
```

## Tests

BATS tests cover the shell logic (SSH-aware vault auth, the OMZ helper dispatch,
secret loading). They run in Gitea Actions on every push (`.gitea/workflows/test.yml`).

```sh
brew install bats-core
bats test/
```
