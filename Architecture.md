# Architecture

Living design doc for this dotfiles setup. We collaborate around this file —
update it whenever a decision changes.

Last updated: 2026-06-28

## Goal

chezmoi-managed dotfiles backed by self-hosted Gitea, layered on an existing
Oh My Zsh install, with strict separation of concerns between shell helpers,
non-secret config, and secrets.

## Components

| Concern | Tool | Notes |
| --- | --- | --- |
| Dotfile management | chezmoi | source dir `~/.local/share/chezmoi` = the git repo |
| Backing remote | Gitea | `https://gitea.stump.rocks/joestump/dotfiles` (private), HTTPS + osxkeychain token |
| Shell framework | Oh My Zsh | pre-installed at `~/.oh-my-zsh`; **never** re-installed or overwritten |
| Per-project config | direnv | `.envrc` files; non-secret only |
| Secrets | OpenBao (`bao`) | `https://vault.stump.rocks`; fetched at runtime, never stored |
| Secret-leak guard | gitleaks | pre-commit hook via `core.hooksPath` |

## What chezmoi manages — and what it must not

chezmoi manages **only**:

- `~/.zshrc` → source `dot_zshrc` (seeded verbatim from the OMZ-generated file; unchanged)
- `~/.oh-my-zsh/custom/*.zsh` → source `dot_oh-my-zsh/custom/*.zsh`

Everything else under `~/.oh-my-zsh/` is owned by OMZ's own self-update and is
excluded by `.chezmoiignore`:

```
.oh-my-zsh/**
!.oh-my-zsh/custom/**
.oh-my-zsh/custom/example.zsh
```

`README.md`, `Architecture.md`, and `examples/` are also ignored so they live in
the repo but are never applied to `$HOME`. (Dot-prefixed repo files like
`.gitignore`, `.gitleaks.toml`, `.githooks/` are ignored by chezmoi
automatically.)

## Separation of concerns (the core constraint)

1. **Shell helpers** — one `*.zsh` file per helper in `$ZSH_CUSTOM`
   (`~/.oh-my-zsh/custom/`). OMZ auto-sources them after `oh-my-zsh.sh`, so no
   manual source-loop in `.zshrc` is needed.
2. **Non-secret config** — direnv `.envrc` (hostnames, ports, AWS profiles,
   regions). See `examples/envrc.example`.
3. **Secrets** — never in env files or the repo. Secret-bearing helpers fetch at
   runtime via `bao kv get` against OpenBao. No dotenvx, no committed `.env`, no
   second secrets path.

## OMZ integration rules

- OMZ already installed → do **not** re-run its installer, do **not** let it
  overwrite `~/.zshrc`.
- `~/.zshrc` is brought under management as-is; **zero content changes** were
  needed (stock OMZ file: `plugins=(git)`, theme `robbyrussell`).
- direnv is hooked via `custom/direnv.zsh` (`eval "$(direnv hook zsh)"`,
  guarded by a `command -v` check) — **not** by editing `.zshrc`.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Repo owner | user `joestump` | personal dotfiles; conventional |
| Git transport | HTTPS + token | existing osxkeychain `oauth2` token for `gitea.stump.rocks` authenticates as admin; no SSH key wiring needed |
| Repo visibility | private | dotfiles are personal |
| Secret-scan hook | committed `.githooks/` + `core.hooksPath` | reproducible without the `pre-commit` Python framework |
| direnv hook location | `custom/direnv.zsh` | keeps `.zshrc` untouched |

## Helpers (current)

- `vault-login <host> [port]` — opens an SSH tunnel to `<host>` forwarding the
  Vault/OpenBao port (default 8250) and runs an OIDC `vault login` on the remote.
  Refuses if the local port is already in use (checked with `lsof`).
- `direnv.zsh` — hooks direnv into the shell.

## Conventions

**Add a helper:** drop a `*.zsh` in `~/.oh-my-zsh/custom/`, `chezmoi add` it,
commit, push.

**Apply elsewhere:** `chezmoi init --apply https://gitea.stump.rocks/joestump/dotfiles.git`,
then `chezmoi update` to pull + apply.

## Open / future ideas

- Add more helpers as needed (aws profile switchers, k8s context helpers).
- Consider a `run_once_` chezmoi script to `brew install` prereqs on new machines.
- Optional: machine-specific config via chezmoi templates if a second host appears.
