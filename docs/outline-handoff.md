<!--
FOR THE AGENT PUBLISHING THIS TO OUTLINE
========================================
- Outline lives at https://outline.stump.rocks. Use the outline-edits skill.
- Create a NEW document. Suggested title (set via the title field, NOT an H1):
    "Dotfiles: chezmoi + Oh My Zsh"
  Suggested collection: an Engineering / Runbooks / Setup collection.
- Outline rule: do NOT begin the body with a top-level H1 — the title is a
  separate field. The content below already starts with body text + H2s, so
  paste it as-is (strip this HTML comment).
- Turn the bare URLs and repo-file references into links where natural. The repo
  is https://gitea.stump.rocks/joestump/dotfiles (private).
- The "Secrets" section describes the intended design; mark it clearly as the
  current/agreed approach.
-->

My personal shell environment is managed with [chezmoi](https://www.chezmoi.io/)
and backed by self-hosted Gitea at
<https://gitea.stump.rocks/joestump/dotfiles> (private). It layers on an existing
[Oh My Zsh](https://ohmyz.sh/) install. This page is the operating manual.

## The one rule: separation of concerns

| Kind | Where it lives | Never |
| --- | --- | --- |
| Shell helper functions | one `*.zsh` file per helper in `~/.oh-my-zsh/custom/` (OMZ auto-sources) | — |
| Non-secret config | direnv `.envrc` per project (hosts, ports, AWS profiles, regions) | — |
| Secrets | OpenBao (`https://vault.stump.rocks`); a Vault Agent renders them on a schedule, OMZ sources them (use the `vault` CLI, not `bao`) | never in a file, `.env`, or the repo |

No dotenvx, no `python-dotenv`, no committed `.env`. A gitleaks pre-commit hook
blocks accidental secret commits.

## What chezmoi manages

chezmoi manages **only** `~/.zshrc` and `~/.oh-my-zsh/custom/`. Oh My Zsh
self-updates everything else under `~/.oh-my-zsh/` (`.chezmoiignore` enforces it).

Two sides to chezmoi:

- **Source** = `~/.local/share/chezmoi` (the git repo; you edit + push here).
- **Target** = `$HOME` (the real files chezmoi writes).

Source names are encoded: `dot_zshrc` → `~/.zshrc`.

## Daily loop

```sh
chezmoi edit ~/.zshrc                 # edit a managed file
chezmoi apply                         # write into $HOME
chezmoi cd                            # into the source repo
git add -A && git commit -m "..." && git push
exit
chezmoi update                        # on another machine: pull + apply
```

## Add a shell helper

```sh
$EDITOR ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi cd && git add -A && git commit -m "Add my-helper" && git push && exit
```

OMZ auto-sources every `*.zsh` in `custom/` — no `.zshrc` edit needed.

## Themes — install many, swap one line

Three themes are installed (cloned via chezmoi externals). Switch by editing
`ZSH_THEME` in `~/.zshrc`, then `exec zsh`:

- `spaceship-prompt/spaceship` — default (favorite)
- `powerlevel10k/powerlevel10k` — run `p10k configure` after switching
- `quantum-zsh/quantum`
- `robbyrussell` — OMZ built-in fallback

Spaceship/Powerlevel10k want a Nerd Font (`brew install --cask font-meslo-lg-nerd-font`).

## Plugins

Edit the `plugins=(...)` array in `~/.zshrc`. Enabled: git, gh, aws, terraform,
kubectl, kubectx, helm, docker, docker-compose, brew, macos, python, pip,
virtualenv, npm, colored-man-pages, dirhistory, extract, jsontools, fzf, zoxide,
zsh-autosuggestions, zsh-syntax-highlighting (this one stays **last**). direnv is
hooked via `custom/direnv.zsh`, not as a plugin.

## "My own OMZ ecosystem" — externals

External repos (themes, non-bundled plugins) are declared in
`.chezmoiexternal.toml` and cloned by chezmoi on apply (not vendored):

```toml
[".oh-my-zsh/custom/plugins/some-plugin"]
    type = "git-repo"
    url = "https://github.com/owner/some-plugin.git"
    refreshPeriod = "168h"
```

Refresh to latest upstream: `chezmoi apply --refresh-externals`.

## Per-project config — direnv

```sh
cd ~/src/myproject
cp ~/.local/share/chezmoi/examples/envrc.example .envrc   # NON-SECRET only
$EDITOR .envrc && direnv allow
```

## Secrets — OpenBao + Vault Agent

Nothing secret is stored in files or the repo. Secrets live in OpenBao; a **Vault
Agent** (launchd) renders them to `~/.config/vault/secrets-*.env` on a schedule —
including short-lived **dynamic AWS** credentials — and `~/.oh-my-zsh/custom/secrets.zsh`
sources them. Use the **`vault`** CLI (the Homebrew `bao` is an unrelated hashing
tool).

```sh
vault-agent status        # agent running?
vault kv put secret/personal/llm OPENAI_API_KEY=sk-new...   # rotate; agent re-renders
```

Authenticate with `vault login -method=oidc` (seeds the token the agent renews).
Full detail lives in the repo at `docs/secrets.md`.

## Set up a brand-new machine (one command)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

This installs Homebrew + tools + Oh My Zsh (without clobbering `.zshrc`), clones
the themes/plugins, applies all dotfiles, and wires the git hook — via chezmoi
`run_once_` bootstrap scripts. Afterward: set a Nerd Font, `vault login -method=oidc`,
and `vault-agent start`.

## Command cheat sheet

| Command | Does |
| --- | --- |
| `chezmoi edit <target>` | edit a managed file |
| `chezmoi add <path>` | start managing a file |
| `chezmoi apply` | render source → `$HOME` |
| `chezmoi diff` | preview pending changes |
| `chezmoi update` | pull + apply |
| `chezmoi managed` | list managed paths |
| `chezmoi apply --refresh-externals` | re-pull external themes/plugins |
