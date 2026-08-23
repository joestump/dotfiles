---
sidebar_position: 9
title: Architecture
---

# Architecture & decisions

The design rationale, distilled. The repo's own
[`Architecture.md`](https://github.com/joestump/dotfiles/blob/main/Architecture.md)
goes deeper and is the living document; this page is the reader-facing summary.

## Separation of concerns (the core constraint)

| Kind | Lives in | Never |
| --- | --- | --- |
| Shell helpers | one `*.zsh` per file in `~/.oh-my-zsh/custom/` (OMZ auto-sources) | — |
| Non-secret config | direnv `.envrc` per project | — |
| Non-secret *shared* config | `.chezmoidata.yaml` | — |
| Identity | derived from `whoami` + OpenBao env | anywhere in the repo |
| Secrets | OpenBao, rendered at runtime by the Vault Agent | in a file, `.env`, or the repo |

## Key decisions

- **Two checkouts, two roles.** Production (`~/.local/share/chezmoi`) is what
  `chezmoi apply` renders from and is pinned to clean upstream `main`; the
  workbench (`~/src/dotfiles`) is an ordinary git repo where development happens
  and which chezmoi never reads. This replaced a single shared checkout whose
  stash-around-pull and drift-advisory machinery existed purely to accommodate
  applying `$HOME` from parked feature branches — the exact entanglement that
  made `czu` fail some way nearly every run. → [Editing](workflow)
- **`run_onchange_` + manifest hashes** so package/MCP/plugin installs re-run only
  when their list changes; **`run_after_`** where the input is an upstream clone
  rather than a file in this repo (an onchange gate would never re-fire).
- **`.chezmoiscripts/`** for installs that aren't files; **externals** for cloned
  upstreams (themes, plugins, marketplaces, the Crush and harness sources).
- **Secrets are OpenBao-authoritative**; the agent renders them so machines stay
  disposable — re-image a node, `czapprole` it, and you're whole again.
- **Machine identity over human login.** Each host gets its own AppRole
  (`vault-agent-<host>`) so one box can be revoked without re-provisioning the
  fleet, and so the agent renews itself instead of dying at an OIDC max-TTL.
- **Never gate a render on the apply-time environment.** A gate evaluated at apply
  time for a secret needed at run time buys nothing and silently produces empty
  config on any non-interactive apply. → [Crush](claude/crush)
- **The render always wins over an app's own writes.** `czu` force-asserts the
  targets applications rewrite in place, rather than letting chezmoi's
  changed-since-last-write guard prompt forever (interactive) or skip silently
  (scheduled).
- **HTTPS + osxkeychain** for the Gitea remote (no SSH-key wiring on the hub).
- **`vault`, not `bao`** — the Homebrew `bao` is an unrelated BLAKE3 tool, a trap
  worth a warning.

## Repo layout

```
dot_zshrc                          → ~/.zshrc
dot_oh-my-zsh/custom/*.zsh         → helpers, prompt, secrets loader
dot_Brewfile                       → ~/.Brewfile
dot_config/dotfiles/               → manifests (apt, go, mcp, plugins) + czu/ui libs
dot_config/private_vault/          → Vault Agent config + Consul-Templates (dir 0700)
dot_config/harness/                → harness.toml — supervised agent definitions
dot_config/crush/                  → Crush config, rules, in-repo skills
dot_config/systemd/user/           → Linux services + timers
dot_config/git/  dot_gitconfig.tmpl→ git config + the Gitea credential helper
dot_claude/                        → composed Claude rules + the chezmoi guard hooks
Library/LaunchAgents/              → macOS launchd plists
.chezmoitemplates/agents/          → the shared agent-rules partials
.chezmoiscripts/                   → run_once_ / run_onchange_ / run_after_ installers
.chezmoiexternal.toml              → cloned themes, plugins, marketplaces, sources
.chezmoidata.yaml                  → non-secret template data (URLs, ssh, contacts)
.githooks/  .gitleaks.toml         → secret-leak prevention
test/  .gitea/workflows/           → BATS + lint + gitleaks CI
website/                           → this Docusaurus site
scripts/  examples/                → repo-only (not applied to $HOME)
docs/                              → stubs pointing at this site
```

## What chezmoi owns

More than it used to. `.chezmoiignore` keeps it out of Oh My Zsh's self-managed
tree (`.oh-my-zsh/*` with `!.oh-my-zsh/custom/`), but inside its own scope
chezmoi is authoritative for the shell, the terminal, git, SSH, the Vault Agent,
both AI harnesses' configs, the agent rules, and every service unit and timer on
both platforms.

The practical consequence: **a hand-edit to any rendered file is temporary.** If
something needs to differ on one box, the mechanism is a per-machine override in
that box's `~/.config/chezmoi/chezmoi.toml` under `[data]` — where maps
deep-merge and lists replace — not an edit to the target.

The canonical repo lives on a private Gitea instance and is the source of
truth; [`joestump/dotfiles`](https://github.com/joestump/dotfiles) on GitHub is
its public read-only mirror.
