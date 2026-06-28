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
| Secrets | OpenBao via `vault` CLI + Vault Agent | `https://vault.stump.rocks`; rendered to env files on a schedule, never committed |
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
3. **Secrets** — never in env files or the repo. A Vault Agent renders them from
   OpenBao to local env files (sourced by `custom/secrets.zsh`). No dotenvx, no
   committed `.env`, no second secrets path. See the Secrets section below.

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

## Portability & "my own Oh My Zsh ecosystem"

Three chezmoi features make this fully portable to any machine with Gitea access:

1. **`chezmoi init --apply <repo>`** — one command clones + applies everything.
2. **`run_once_` scripts** — `run_once_before_10-install-prereqs.sh` installs
   Homebrew, the CLI tools, and Oh My Zsh (with `KEEP_ZSHRC=yes` so it never
   clobbers the managed `.zshrc`); `run_once_after_20-configure-git-hooks.sh`
   wires `core.hooksPath` (not carried by `git clone`).
3. **`.chezmoiexternal.toml`** — declares external git repos (themes + external
   plugins) that chezmoi clones into `~/.oh-my-zsh/custom/` on apply and keeps
   refreshed. This is the "own ecosystem" layer: curated upstreams, not vendored.

## Themes & plugins

- Themes (externals, swap via `ZSH_THEME`): `spaceship-prompt/spaceship`
  (default — Joe's favorite), `powerlevel10k/powerlevel10k`, `quantum-zsh/quantum`.
  Installing many and switching by one line is supported.
- External plugins (externals): `zsh-autosuggestions`, `zsh-syntax-highlighting`
  (kept last in `plugins=()`).
- Bundled plugins enabled: git, gh, aws, terraform, kubectl, kubectx, helm,
  docker, docker-compose, brew, macos, python, pip, virtualenv, npm,
  colored-man-pages, dirhistory, extract, jsontools, fzf, zoxide.
- `direnv` is hooked via `custom/direnv.zsh`, NOT the OMZ direnv plugin (avoids a
  double hook; keeps the hook explicit and guarded).

## Secrets — OpenBao + Vault Agent

CLIENT: use the HashiCorp **`vault`** CLI (API-compatible with the OpenBao 2.5.0
server). The Homebrew `bao` is the unrelated BLAKE3 hashing tool — NOT OpenBao;
an earlier draft wrongly wired `[vault] command = "bao"` and was removed.

Design (Joe's choice: Vault Agent + OMZ loader + dynamic AWS):

- **Vault Agent** under launchd (`rocks.stump.vault-agent`) auto-auths via
  `token_file` (`~/.vault-token`, seeded by an interactive `vault login -method=oidc`),
  renews the token, and renders env files on a schedule. Validated: config parses
  and the agent authenticates against the live server.
- **Templates** (Consul-Template `*.ctmpl`, kept separate from chezmoi templating):
  `secrets-static.env` ← KV `secret/personal/*`; `secrets-aws.env` ← dynamic
  `aws/creds/personal-cli`. `exit_on_retry_failure=false` so a not-yet-configured
  engine doesn't crash the agent.
- **OMZ loader** `custom/secrets.zsh` sources `~/.config/vault/secrets-*.env`
  (guarded). `custom/vault-agent.zsh` provides `vault-agent {start|stop|status|log|env}`.
- Repo holds config + templates + the loader (paths only); rendered `*.env` files
  (0600) are never committed.

Static secrets stay in KV (`secret/personal/{llm,gitea,pocketid,garage}`); **AWS
moves to dynamic, short-lived credentials** (auto-rotated by the agent), retiring
the static AWS keys entirely.

Remaining (Joe-owned): `vault login` → `scripts/load-static-secrets.sh` →
`scripts/openbao-aws-setup.sh` (server-side, admin + AWS root cred) →
`vault-agent start` → verify → strip secret lines from `~/.zprofile` → rotate the
previously-exposed credentials. Runbook: `docs/secrets.md`.

## Open / future ideas

- Complete the secrets bring-up (load KV, set up dynamic AWS, start agent, strip
  `~/.zprofile`); see the Secrets section.
- Add more helpers as needed (aws profile switchers, k8s context helpers).
- Optional: machine-specific config via chezmoi templates if hosts diverge.
- Nerd Font cask in bootstrap if a non-interactive font install is acceptable.
