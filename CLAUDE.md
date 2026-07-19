# Working on this repo (Claude, read this first)

This is Joe's chezmoi-managed dotfiles repo (source of truth: `~/.local/share/chezmoi`, remote: https://gitea.stump.rocks/joestump/dotfiles). It is a **production service** — every StumpCloud node, every ephemeral SSH bootstrap, and every Claude Code session on Joe's machines runs on what lands here. Breakage here has OMG scope (see `~/.claude/CLAUDE.md` § "OMGs").

Before you edit anything, load the `/chezmoi` skill (`.claude/skills/chezmoi/SKILL.md`) — it encodes the source-vs-target rules, the run-script prefixes, the ui-lib.sh + gum theme, the externals model, and the Vault Agent secrets flow. Ignoring those conventions will silently break other machines on the next `chezmoi apply`.

## Where to look

- **[Architecture.md](Architecture.md)** — the living design doc (components, decisions, separation of concerns, secrets flow). Read before proposing structural changes.
- **[docs/](docs/)** — human-facing runbooks: `bootstrap-new-machine.md`, `packages.md`, `secrets.md`, `usage.md`.
- **[dot_oh-my-zsh/custom/](dot_oh-my-zsh/custom/)** — every zsh helper lives here as one file per concern (`dot.zsh`, `chezmoi.zsh.tmpl`, `vault-agent.zsh`, `signal-daemon.zsh`, `gum-ui.zsh`, `motd.zsh`, `00-secrets.zsh`, etc.). OMZ auto-sources them; no `source` lines in `.zshrc`.
- **[.chezmoiscripts/](.chezmoiscripts/)** — apply-time run scripts (`run_once_`, `run_onchange_`, `run_after_`). Ordered numerically (`10-`, `40-`, `42-`, …). Every one sources `~/.config/dotfiles/ui-lib.sh` (source: [dot_config/dotfiles/ui-lib.sh](dot_config/dotfiles/ui-lib.sh)) so their output matches czu's headings + ticks.
- **[.chezmoiexternal.toml](.chezmoiexternal.toml)** — pinned upstream git repos (OMZ plugins, themes, the private Gitea skills marketplace, vim-plug). Every git-repo external MUST carry `[X.pull] args = ["--ff-only", "--quiet"]` — the `--quiet` is what keeps czu's output clean.
- **[.chezmoidata.yaml](.chezmoidata.yaml)** — non-secret template data (`.signalNumber`, `.githubUser`, `.email`, `.shlinkApiUrl`). Reference in any `.tmpl` file.

## Non-obvious rules

- **Never edit `~/.<file>` directly** if it's chezmoi-managed. Edit the source under `~/.local/share/chezmoi/` (or use `chezmoi edit <target>`), then `chezmoi apply`. The next apply on any other machine will clobber a rendered-file edit.
- **Never re-run the OMZ installer or touch `~/.oh-my-zsh/` outside `custom/`.** OMZ self-updates; we only own `custom/*`. See `.chezmoiignore`.
- **Secrets never live in the repo.** Vault Agent renders `~/.config/vault/secrets-*.env` from OpenBao on a schedule; `custom/00-secrets.zsh` sources them. If you catch a `.env` file or a hardcoded token about to be committed, stop — the gitleaks pre-commit hook (`.githooks/pre-commit`) will block it anyway.
- **Match the visible style.** All apply-time output flows through ui-lib.sh (`heading "📦 …"`, `item ok "…"`, `step "title" -- cmd`). New scripts must too — a raw `echo` in the middle of czu output is a bug. Palette: pink 213, mauve 177, sky 117, green 150 (ok), red 210 (bad), yellow 223 (warn), dim 244.
- **Claude plugins propagate via [dot_config/dotfiles/claude-plugins.tsv.tmpl](dot_config/dotfiles/claude-plugins.tsv.tmpl).** Local marketplaces are fingerprinted by clone HEAD; sentinels live under `~/.config/dotfiles/.claude-plugin-state/`. Bump the tsv, `chezmoi apply --refresh-externals`, done.

## Commit + push

- gitleaks scans every commit via `core.hooksPath = .githooks`. If it blocks, do not `--no-verify` — find the leaked secret.
- Test edits to shell helpers with `bats test/` (bats-core).
- Push to Gitea (`origin`). GitHub is not a mirror.

## Quick reference

| Task | Command |
|---|---|
| See what would change | `chezmoi diff` |
| Apply | `chezmoi apply` |
| Sync + apply + restart Vault Agent | `czu` |
| Bootstrap a fresh node | `czinit joestump@<host>` |
| Force refresh of externals | `chezmoi apply --refresh-externals` |
| Health panel | `status` |
| Action hub | `dot` |
