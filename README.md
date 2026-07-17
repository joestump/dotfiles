# dotfiles

Personal dotfiles, managed with [chezmoi](https://www.chezmoi.io/), backed by
self-hosted Gitea at <https://gitea.stump.rocks/joestump/dotfiles> (mirrored to
[GitHub](https://github.com/joestump/dotfiles), docs mirror at
<https://joestump.github.io/dotfiles/>), and
layered on an existing [Oh My Zsh](https://ohmyz.sh/) install. Hub-and-spoke:
one macOS hub (required — parts of the stack have no Linux desktop apps), any
number of Linux spokes. Full docs, including install:
<https://joestump.pages.stump.rocks/dotfiles/>

chezmoi manages `~/.zshrc`, `~/.oh-my-zsh/custom/`, and several config trees
(`~/.Brewfile`, `~/.config/{vault,ghostty,dotfiles,chezmoi}`, `~/.config/git/`,
`Library/LaunchAgents/`, and install scripts under `.chezmoiscripts/`). OMZ
self-updates the rest of its tree, guarded by `.chezmoiignore`.

Full docs at the **[published website](https://joestump.pages.stump.rocks/dotfiles/)**
(`website/docs/` is the canonical source).

## Docs

The reader-facing docs live on the **[published site](https://joestump.pages.stump.rocks/dotfiles/)**
(`website/docs/` is the canonical source; the stubs under `docs/` just point here):

- **[Day-to-day usage](https://joestump.pages.stump.rocks/dotfiles/docs/overview)** — add helpers, swap themes, plugins, direnv.
- **[Packages & tooling](https://joestump.pages.stump.rocks/dotfiles/docs/packages)** — declarative tooling (Brewfile, Go tools) on macOS + Ubuntu.
- **[Secrets](https://joestump.pages.stump.rocks/dotfiles/docs/secrets)** — OpenBao + Vault Agent: how secrets reach your shell.
- **[Bootstrap a new machine](https://joestump.pages.stump.rocks/dotfiles/docs/install/mothership)** — one-command setup on any machine.
- **[Architecture.md](Architecture.md)** — design rationale and decisions (repo-local).

## Set up on a new machine (one command)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

Installs Homebrew + tools + Oh My Zsh, clones themes/plugins, and applies
everything. To bootstrap a **remote** box (ie01/ie02) from your laptop in one
step: `chezmoi ssh <host> https://gitea.stump.rocks/joestump/dotfiles.git`.
See the [install docs](https://joestump.pages.stump.rocks/dotfiles/docs/install/mothership).

## Separation of concerns

| Kind | Where it lives | Example |
| --- | --- | --- |
| Shell helper functions | one `*.zsh` per helper in `~/.oh-my-zsh/custom/` (OMZ auto-sources) | `dot_oh-my-zsh/custom/vault-login.zsh` |
| Non-secret config | direnv `.envrc` per project | [`examples/envrc.example`](examples/envrc.example) |
| Secrets | **never** in files or this repo — held in OpenBao (<https://vault.stump.rocks>); a Vault Agent renders them on a schedule and OMZ sources the result | [Secrets](https://joestump.pages.stump.rocks/dotfiles/docs/secrets) |

No dotenvx. No `python-dotenv`. No committed `.env`. A `gitleaks` pre-commit hook
blocks accidental secret commits.

## What's in here

```
dot_zshrc                          → ~/.zshrc  (theme + plugins; seeded from OMZ)
dot_oh-my-zsh/custom/*.zsh         → ~/.oh-my-zsh/custom/  (helpers + secrets loader)
dot_Brewfile                       → ~/.Brewfile  (declarative tooling; brew bundle)
dot_config/dotfiles/               → manifests (apt-packages, go-tools, MCP defs, UI libs)
dot_config/vault/                  → Vault Agent config + Consul-Templates
dot_config/git/                    → git config + Gitea credential helper
dot_config/chezmoi/                → chezmoi config (autoCommit/autoPush)
dot_config/crush/                  → Crush (AI coding assistant) config
dot_claude/                        → Claude Code project instructions
Library/LaunchAgents/              → macOS launchd plists (vault-agent, signal, czu)
.chezmoiscripts/                   → install + service-setup scripts (run on apply)
.chezmoidata.yaml                  → non-secret template data (URLs, signal number)
.chezmoiexternal.toml              → clones themes + external plugins on apply
run_onchange_after_10-*.tmpl       → package install (Brewfile/apt + Go tools + Claude)
run_once_before_10-*.sh            → bootstrap: Homebrew + Oh My Zsh (+ apt prereqs)
.chezmoiignore                     → keep chezmoi out of OMZ's self-managed tree
.githooks/  .gitleaks.toml         → secret-leak prevention
website/                           → Docusaurus site (published via Gitea Pages)
examples/  scripts/  test/         → repo-only (not applied to $HOME)
docs/                              → stubs pointing to the canonical website pages
```

### Themes (swap via `ZSH_THEME` in `~/.zshrc`)

`spaceship-prompt/spaceship` (default) · `powerlevel10k/powerlevel10k` ·
`quantum-zsh/quantum` · `comfyline_prompt/comfyline`. Installed as externals — see
[the docs](https://joestump.pages.stump.rocks/dotfiles/docs/overview).

## Add a helper (quick reference)

```sh
$EDITOR ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi cd && git add -A && git commit -m "Add my-helper" && git push && exit
```

## Tests

BATS tests cover the shell logic (SSH-aware vault auth, the OMZ helper dispatch,
secret loading). They run in Gitea Actions on every push (`.gitea/workflows/ci.yml`).

```sh
brew install bats-core
bats test/
```
