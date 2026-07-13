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

chezmoi manages:

- `~/.zshrc` → source `dot_zshrc` (seeded verbatim from the OMZ-generated file)
- `~/.oh-my-zsh/custom/*.zsh` → source `dot_oh-my-zsh/custom/*.zsh`
- `~/.Brewfile` → source `dot_Brewfile` (declarative tooling)
- `~/.config/{vault,dotfiles,ghostty,git,chezmoi,crush}/` → config trees
- `~/.claude/CLAUDE.md` → Claude Code project instructions
- `Library/LaunchAgents/` → macOS launchd plists (vault-agent, signal, czu)
- `.chezmoiscripts/` → install + service-setup scripts

Everything else under `~/.oh-my-zsh/` is owned by OMZ's own self-update and is
excluded by `.chezmoiignore`:

```
.oh-my-zsh/*
!.oh-my-zsh/custom/
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
   OpenBao to local env files (sourced by `custom/00-secrets.zsh`). No dotenvx, no
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
| Outline MCP capability boundary | text-only docs + presigned URLs; no byte uploads via MCP | Outline MCP server exposes `create_attachment` (presign-only), `fetch`, `create_document`, `update_document`, etc., but **cannot upload file bytes via MCP**; `create_attachment` returns a presigned URL and fallback `files.create` requires the API token in the shell. Until upstream Outline ships `upload_attachment` tool (outline/outline#11823), agents degrade to text-only docs + scratchpad screenshot references by design. Remove this caveat when the updated Outline lands. |

## Helpers (current)

- `vault-login <host> [port]` — opens an SSH tunnel to `<host>` forwarding the
  Vault/OpenBao port (default 8250) and runs an OIDC `vault login` on the remote.
  Refuses if the local port is already in use (checked with `lsof`).
- `direnv.zsh` — hooks direnv into the shell.
- `czu` — the interactive command IS a thin wrapper around
  `dot_config/dotfiles/executable_czu-run.zsh`, which also runs unattended every 6h
  via a launchd LaunchAgent (`rocks.stump.czu`) / systemd --user timer (`czu.timer`)
  — one implementation, two callers. On failure it Signal-pings once (transition-
  based, mirrors `vault-agent-stale`, not every tick) via the shared
  `dot_config/dotfiles/signal-notify.sh.tmpl` lib.

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

Design (Joe's choice: Vault Agent + OMZ loader + AppRole auto-auth):

- **Vault Agent** under launchd (`rocks.stump.vault-agent`) auto-auths via
  **AppRole** (role_id + secret_id, provisioned by `czapprole`/`czinit`), giving
  the agent a self-renewing periodic token that never hits a max-TTL. The legacy
  `token_file` auth (~/.vault-token from an interactive OIDC login) is kept as a
  fallback only. The agent renews and renders env files on a schedule.
- **Per-user KV layout.** Each identity's secrets live under
  `secret/users/<os-login>/<category>` (e.g. `secret/users/joestump/gitea`,
  `secret/users/joestump-agent/gitea`), so hosts sharing one OpenBao never cross
  identities. The render is scoped by `$USER`, which the Vault Agent service
  exports (`vault-agent.service.tmpl` / the launchd plist).
- **Templates** (Consul-Template `*.ctmpl`, kept separate from chezmoi templating):
  `secrets-static.env` ← KV `secret/users/$USER/*`; `secrets-aws.env` ← static KV
  `secret/users/$USER/aws`. `exit_on_retry_failure=false` so a not-yet-configured
  engine doesn't crash the agent.
- **SSH keys use the same auto-discovery as env vars.** `ssh-keys.ctmpl` ranges
  over every field of `secret/users/$USER/ssh` and `writeToFile`s each to
  `~/.ssh/<field>` (`*.pub` → 0644, else 0600), so `id_rsa`, `id_ed25519`, or any
  future key just appears — no per-key template, no gating. An absent/empty ssh
  bag writes nothing under `~/.ssh` (only a names-only manifest), so it can never
  clobber a key. `$USER`/`$HOME` come from the Vault Agent service env.
- **OMZ loader** `custom/00-secrets.zsh` sources `~/.config/vault/secrets-*.env`
  (guarded). `custom/vault-agent.zsh` provides `vault-agent {start|stop|status|log|env}`.
- Repo holds config + templates + the loader (paths only); rendered `*.env` files
  (0600) are never committed.

Static secrets stay in KV (`secret/users/<you>/{llm,gitea,pocketid,garage}`); **AWS
credentials** are also static KV (`secret/users/<you>/aws`), rendered by the agent
into `secrets-aws.env`. (An earlier design planned dynamic `aws/creds/` creds, but
the static KV approach is what shipped.)

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
