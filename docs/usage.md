# Using this setup

Day-to-day guide for the chezmoi + Oh My Zsh dotfiles at
<https://gitea.stump.rocks/joestump/dotfiles>.

## Mental model

chezmoi has two sides:

| | Path | What it is |
| --- | --- | --- |
| **Source** | `~/.local/share/chezmoi` | the git repo. You edit here (or via `chezmoi` commands) and `git push`. |
| **Target** | your `$HOME` | the real files chezmoi writes (`~/.zshrc`, `~/.oh-my-zsh/custom/*`). |

Source filenames are encoded: `dot_zshrc` → `~/.zshrc`,
`dot_oh-my-zsh/custom/foo.zsh` → `~/.oh-my-zsh/custom/foo.zsh`.
`chezmoi apply` renders source → target. `chezmoi managed` lists what it owns.

chezmoi manages **only** `~/.zshrc` and `~/.oh-my-zsh/custom/`. Everything else
under `~/.oh-my-zsh/` is owned by Oh My Zsh's own self-update (`.chezmoiignore`
enforces this).

## The everyday loop

```sh
chezmoi edit ~/.zshrc        # edit a managed file in the source repo
chezmoi apply                # write changes into $HOME
chezmoi cd                   # cd into the source repo
git add -A && git commit -m "..." && git push
exit                         # leave the source-repo subshell
```

Pull changes made on another machine:

```sh
chezmoi update               # git pull + apply in one step
```

See what would change before applying:

```sh
chezmoi diff
```

## Add a shell helper

One file per helper, dropped in `~/.oh-my-zsh/custom/` — Oh My Zsh auto-sources
every `*.zsh` there, so no edit to `.zshrc` is needed.

```sh
$EDITOR ~/.oh-my-zsh/custom/my-helper.zsh   # define a function
chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi cd && git add -A && git commit -m "Add my-helper" && git push && exit
```

## Swap the prompt theme

Three themes are installed (cloned via chezmoi externals). Switch by editing the
`ZSH_THEME` line in `~/.zshrc` and opening a new shell:

| `ZSH_THEME` value | Theme |
| --- | --- |
| `spaceship-prompt/spaceship` | Spaceship (default) |
| `powerlevel10k/powerlevel10k` | Powerlevel10k — run `p10k configure` once after switching |
| `quantum-zsh/quantum` | Quantum |
| `comfyline_prompt/comfyline` | ComfyLine (needs a Powerline/Nerd font) |
| `robbyrussell` | OMZ built-in fallback |

```sh
chezmoi edit ~/.zshrc        # change ZSH_THEME=...
chezmoi apply
exec zsh                     # reload
chezmoi cd && git commit -am "Switch theme" && git push && exit
```

> Spaceship and Powerlevel10k render best with a [Nerd Font](https://www.nerdfonts.com/)
> (e.g. `brew install --cask font-meslo-lg-nerd-font`) selected in your terminal.

## Add / remove OMZ plugins

Edit the `plugins=(...)` array in `~/.zshrc`. Bundled plugins live in
`~/.oh-my-zsh/plugins/`; list them with `ls ~/.oh-my-zsh/plugins`.

> `zsh-syntax-highlighting` must stay **last** in the array.
> `direnv` is deliberately **not** a plugin here — it's hooked via
> `~/.oh-my-zsh/custom/direnv.zsh` so the hook is explicit and guarded.

### History autosuggestions + Tab

`zsh-autosuggestions` shows the grayed-out completion from your history. Accept it
with **→ / End** (built-in) or **Tab** (added by `custom/autosuggest-tab.zsh`).
When no suggestion is showing, Tab does normal completion (fzf-aware). To accept
with a different key instead, edit that file's `bindkey` line.

## Add an external plugin or theme (the "ecosystem")

External repos (not bundled with OMZ) are declared in `.chezmoiexternal.toml` and
cloned by chezmoi on apply — they are **not** vendored into this repo.

```toml
[".oh-my-zsh/custom/plugins/some-plugin"]
    type = "git-repo"
    url = "https://github.com/owner/some-plugin.git"
    refreshPeriod = "168h"
```

Then `chezmoi apply` clones it, and add `some-plugin` to `plugins=(...)`.
Refresh all externals to latest upstream:

```sh
chezmoi apply --refresh-externals
```

## direnv — per-project NON-SECRET config

direnv loads a project's `.envrc` when you `cd` into it. Use it for non-secret
config only (hostnames, ports, AWS profiles, regions). See
[`examples/envrc.example`](../examples/envrc.example).

```sh
cd ~/src/myproject
cp ~/.local/share/chezmoi/examples/envrc.example .envrc
$EDITOR .envrc
direnv allow
```

## Secrets — OpenBao + Vault Agent

Secrets are **never** committed or written to `.envrc`/`.zprofile` by hand. They
live in OpenBao (<https://vault.stump.rocks>); a **Vault Agent** renders them to
`~/.config/vault/secrets-*.env` on a schedule and `~/.oh-my-zsh/custom/secrets.zsh`
sources them — including short-lived dynamic AWS credentials. Use the **`vault`**
CLI (the Homebrew `bao` is the unrelated BLAKE3 tool).

```sh
vault-agent status        # is the agent running?
vault-agent env           # what it has rendered
vault kv put secret/personal/llm OPENAI_API_KEY=sk-new...   # rotate a secret
```

Full design + one-time bring-up: **[docs/secrets.md](secrets.md)**. The gitleaks
pre-commit hook blocks any accidental secret commit to this repo.

## Command cheat sheet

| Command | Does |
| --- | --- |
| `chezmoi edit <target>` | edit a managed file in the source repo |
| `chezmoi add <path>` | start managing a file |
| `chezmoi apply` | render source → `$HOME` |
| `chezmoi diff` | preview pending changes |
| `chezmoi update` | `git pull` + apply |
| `chezmoi managed` | list managed paths |
| `chezmoi cd` | open a shell in the source repo |
| `chezmoi apply --refresh-externals` | re-pull external themes/plugins |

## Troubleshooting

- **A change didn't take** — run `chezmoi diff`; you probably edited the target
  (`~/.zshrc`) directly instead of the source. `chezmoi add` re-captures it, or
  `chezmoi apply` overwrites it from source.
- **Theme not found** — `chezmoi apply --refresh-externals` to (re)clone it.
- **`can't change option: zle`** — only appears in non-interactive/no-TTY shells
  (scripts); harmless and absent in a real terminal.
