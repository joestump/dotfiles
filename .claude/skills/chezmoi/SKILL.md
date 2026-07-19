---
name: chezmoi
description: >
  Working reference for Joe's chezmoi-managed dotfiles repo at
  ~/.local/share/chezmoi (source of truth for every StumpCloud node's shell +
  helpers + secrets flow). Load this whenever the task edits a file in this
  repo — adding a helper, changing a run script, adjusting an external, wiring
  secrets, extending the czu/status/dot commands, or updating the ui-lib style.
  Bakes in source-vs-target rules, the run_once/run_onchange/run_after prefix
  ordering, the ui-lib.sh + gum theme palette, the OpenBao/Vault Agent
  secrets flow, the externals model, and the Claude-plugins tracking mechanism
  — so you edit in the right place and match the visible style instead of
  re-deriving them by grep.
---

# Working on the dotfiles repo

Joe's dotfiles are chezmoi-managed and portable across every machine he touches. **The source is the canonical form; the rendered files under `$HOME` are throwaway.** Editing rendered files loses the change on the next `chezmoi apply` from any node. That is the single biggest way to break this repo — everything else in this doc follows from it.

Companion docs (read as needed, not upfront):

- [Architecture.md](../../../Architecture.md) — the living design doc: components, decisions, secrets architecture.
- [docs/bootstrap-new-machine.md](../../../docs/bootstrap-new-machine.md), [docs/secrets.md](../../../docs/secrets.md), [docs/usage.md](../../../docs/usage.md), [docs/packages.md](../../../docs/packages.md).

## Source vs. target — the naming convention

chezmoi's source tree lives at `~/.local/share/chezmoi/`. Rendered targets land in `$HOME`. The mapping is done by filename prefix.

| Source | Target | Notes |
|---|---|---|
| `dot_zshrc` | `~/.zshrc` | `dot_` → `.` |
| `dot_oh-my-zsh/custom/dot.zsh` | `~/.oh-my-zsh/custom/dot.zsh` | Nested `dot_` works the same |
| `dot_zshrc.tmpl` | `~/.zshrc` | `.tmpl` → run through Go templating first |
| `dot_config/dotfiles/claude-plugins.tsv.tmpl` | `~/.config/dotfiles/claude-plugins.tsv` | Both prefixes stack |
| `run_once_before_10-install-prereqs.sh` | (executed once, in $HOME) | `run_` files are scripts, not artifacts |
| `.gitignore`, `.githooks/`, `CLAUDE.md`, `Architecture.md`, `README.md`, `docs/`, `scripts/`, `test/`, `examples/`, `website/`, `dist/`, `Library/` (non-macOS), `.config/systemd/` (non-Linux) | (ignored) | See [.chezmoiignore](../../../.chezmoiignore). Literal dot-prefixed repo files are auto-ignored |

**Adding a new file that should NOT be applied to `$HOME`** — either dot-prefix its name at the repo root (auto-ignored) or add it to `.chezmoiignore`. This is why `CLAUDE.md` and `Architecture.md` are listed in `.chezmoiignore` explicitly.

**Editing flow.** Prefer editing the source file directly (it's what you're already looking at in the repo). `chezmoi edit <target>` opens the mapped source in `$EDITOR` and auto-applies on save — handy for one-off shell edits, but from Claude the direct edit is simpler. Always `chezmoi apply` (or run `czu`) to render.

## Templating — `.tmpl`

A `.tmpl` suffix runs the file through Go's `text/template` with chezmoi variables and data available. **Non-secret template data** lives in [.chezmoidata.yaml](../../../.chezmoidata.yaml):

| Variable | Value | Where used |
|---|---|---|
| `{{ .signalNumber }}` | `+12062257886` | Signal daemon, MCP config, note-to-self helpers |
| `{{ .githubUser }}` | `joestump` | External URLs, git credential helper, claude-plugins.tsv |
| `{{ .email }}` | `joe@stump.rocks` | Kept for future use; not currently referenced |
| `{{ .shlinkApiUrl }}` | `https://u.stu.mp` | env.zsh (`SHLINK_API_URL`) |

Machine facts (`{{ .chezmoi.os }}`, `{{ .chezmoi.hostname }}`, `{{ .chezmoi.username }}`) are always available.

**When to add a `.tmpl` suffix:** when the file needs a chezmoi variable, per-OS branching (`{{ if eq .chezmoi.os "darwin" }}…{{ end }}`), or per-host branching. When in doubt, leave the file untemplated — a `.tmpl` suffix incurs a re-render on every apply.

**Never put a secret in `.chezmoidata.yaml`** — it's committed. Secrets flow through Vault Agent (below).

## Run scripts — order, gating, and style

`.chezmoiscripts/` (and root-level `run_*` files) execute during `chezmoi apply`. The prefix names its gate:

| Prefix | Fires |
|---|---|
| `run_once_` | Once per machine, ever. State recorded in chezmoi's persistent state |
| `run_onchange_` | Whenever the rendered script content changes |
| `run_after_` | Every apply, unconditionally |
| `run_before_` / `run_after_` | Ordering relative to file operations |

Numeric prefixes (`10-`, `40-`, `42-`, `50-`) order within a phase. Existing conventions:

- `10-install-packages` — Homebrew + Go tools
- `20-configure-git-hooks` — `core.hooksPath`
- `30-default-shell` — chsh to zsh
- `40-vault-agent-service` / `41-vault-agent-stale` — Vault Agent lifecycle
- `42-signal-daemon-service` — signal-cli daemon
- `45-signal-mcp-venv` — Signal MCP `uv` venv (Linux only)
- `46-vim-plug-install` — vim `PlugInstall` when vimrc changed
- `50-ghostty-terminfo` — Ghostty terminfo shipping
- (unnumbered) — `install-claude-plugins`, `install-cgg`, `install-qmd`, `claude-*-mcp-merge`

**Every run script MUST source [ui-lib.sh](../../../dot_config/dotfiles/ui-lib.sh)** so its output composes with the rest of `chezmoi apply` / `czu`. The idiom:

```bash
. "$HOME/.config/dotfiles/ui-lib.sh" 2>/dev/null || {
  # fallback so a fresh node without ui-lib applied yet doesn't break
  heading() { printf '\n== %s ==\n' "$*"; }
  item() { shift; echo "    - $*"; }
  step() { shift; [ "${1:-}" = "--" ] && shift; "$@"; }
  say()  { echo "  $*"; }; warn() { echo "  WARN: $*" >&2; }
}

heading "🔌 My section"
step "widget install" -- some-command
item ok "widget configured"
```

## ui-lib.sh — the visual grammar

Source: [dot_config/dotfiles/ui-lib.sh](../../../dot_config/dotfiles/ui-lib.sh). API:

- `heading "📦 Homebrew"` — pink-bold section title (gum on TTY, plain otherwise).
- `item ok|no|dim "text"` — indented tick line. `ok`=green ✓, `no`=red ✗, `dim`=grey ·.
- `step "Title" -- cmd args…` — spinner while `cmd` runs, then a persistent ✓/✗. Command stderr/stdout is tucked into `~/.cache/chezmoi-apply.log` when off a TTY.
- `spin "Title" -- cmd args…` — same as `step` but no persistent tick (use when the following `item` list will report per-thing).
- `say "…"` / `warn "…"` — single-line status.

**Palette** (Catppuccin-ish 256-color; matches the spaceship prompt + MOTD): pink 213, mauve 177, sky 117, green 150 (ok), red 210 (bad), yellow 223 (warn), dim 244. When calling `gum style --foreground <N>` directly, use these; do not invent a new palette.

## gum theming — shared env

Source: [dot_oh-my-zsh/custom/gum-ui.zsh](../../../dot_oh-my-zsh/custom/gum-ui.zsh). Sets `GUM_CHOOSE_*`, `GUM_FILTER_*`, `GUM_INPUT_*`, `GUM_SPIN_*` env vars so every interactive prompt inherits the palette. Any new helper using `gum choose|filter|input|confirm|spin` gets themed for free — just source (or inherit) this file. Guard interactive widgets with `[[ -t 0 && -t 1 ]] || return`; guard availability with `_have gum || return`.

## Externals — the "own ecosystem" layer

[.chezmoiexternal.toml](../../../.chezmoiexternal.toml) declares external upstreams (OMZ plugins, themes, the private Gitea Claude-plugins marketplace, vim-plug, signal-mcp on Linux). chezmoi clones them into their target paths and refreshes on `refreshPeriod`.

**Rule** — every `git-repo` external MUST have a `[<path>.pull] args = ["--ff-only", "--quiet"]` block. The `--quiet` is what keeps the czu output clean (without it, every refresh dumps `remote: … / Fast-forward / diffstat` chatter into the terminal). The `--ff-only` prevents accidental merge commits in the external clone.

**Add a new external** — copy an existing block. Public repo → HTTPS. Private Gitea → HTTPS with the `.githubUser` template + let the machine's git-credential store carry the token (seeded by `czinit`). Force an immediate refresh with `chezmoi apply --refresh-externals`.

## Secrets — OpenBao + Vault Agent

Documented deeply in [docs/secrets.md](../../../docs/secrets.md) and Architecture.md § "Secrets". Rules:

- **Never commit a secret.** No `.env` files with values, no hardcoded tokens. gitleaks (`.githooks/pre-commit`) will block a commit that leaks one, but the real defense is not putting it there.
- **Static secrets** live in OpenBao KV under `secret/personal/*`. The Vault Agent (`rocks.stump.vault-agent` under launchd on macOS, `vault-agent` systemd --user on Linux) renders them to `~/.config/vault/secrets-static.env` (mode 0600). `custom/00-secrets.zsh` sources it into the shell.
- **AWS credentials** are dynamic — the agent renders `secrets-aws.env` from `aws/creds/personal-cli`. Short-lived, auto-rotated.
- **Machine identity**: new nodes provision via AppRole (`czapprole <host>`), not OIDC. AppRole gives a self-renewing token; OIDC dies at max-TTL. See the 2026-07-01 OMG for the "why".
- **`vault-agent {start|stop|status|log|env}`** — the operator interface. In `custom/vault-agent.zsh`.
- To add a new secret: put it in KV, add a `.ctmpl` template that pulls it (in `dot_config/vault/`), reload the agent (`vault-agent restart`), source the env.

## Claude plugins — installed + kept fresh

[dot_config/dotfiles/claude-plugins.tsv.tmpl](../../../dot_config/dotfiles/claude-plugins.tsv.tmpl) is the manifest — one line per plugin, `<marketplace-source>\t<plugin>@<marketplace-name>`. The install script [.chezmoiscripts/run_after_31-install-claude-plugins.sh.tmpl](../../../.chezmoiscripts/run_after_31-install-claude-plugins.sh.tmpl) runs every apply and:

- **Local-path marketplaces** (the private Gitea one, cloned to `~/.config/claude-marketplaces/claude-personal` via an external): fingerprints the clone's git HEAD in a sentinel under `~/.config/dotfiles/.claude-plugin-state/`. When HEAD moves → reinstalls (because plugin `version` bumps are unreliable).
- **Remote marketplaces** (GitHub `owner/repo`): install-once; refreshed via `claude plugin update <plugin>@<mp>`.

**Add a plugin** — one line in the tsv, `chezmoi apply`. Push a new skill to the private marketplace and want it now? `chezmoi apply --refresh-externals` pulls the clone; the install script sees the moved HEAD and reinstalls.

The `status` command (in `dot_oh-my-zsh/custom/dot.zsh`) reads this tsv + the sentinel dir to show `🔌 skills   N/M fresh`.

## Commands you already have

| Command | Where | Purpose |
|---|---|---|
| `chezmoi apply` | chezmoi | Render + apply |
| `chezmoi diff` | chezmoi | Show what apply would do |
| `chezmoi edit <target>` | chezmoi | Open source in `$EDITOR`, auto-apply on save |
| `czu` | [chezmoi.zsh.tmpl](../../../dot_oh-my-zsh/custom/chezmoi.zsh.tmpl) | Pull + apply + reload Vault Agent + `exec zsh` |
| `czinit <user@host>` | same | Bootstrap a fresh node end-to-end over SSH |
| `czapprole <host>` | vault-approle.zsh | Provision AppRole machine identity |
| `status` | [dot.zsh](../../../dot_oh-my-zsh/custom/dot.zsh) | Health panel (vault, signal, dotfiles drift, skills, disk) |
| `dot` | same | Interactive action hub (calls czu / theme / status / …) |
| `theme` | same | Switch prompt theme (persisted per-machine in `~/.config/dotfiles/zsh-theme`) |
| `vault-agent {start\|stop\|status\|log\|env}` | vault-agent.zsh | Manage the local Vault Agent |
| `vault-login <host>` / `vault-oidc-login` | vault-*.zsh | Interactive OIDC (fallback for machines without AppRole) |
| `signal-daemon {start\|stop\|status\|…}`, `signal-link` | signal-daemon.zsh | signal-cli daemon control |

## Testing + committing

- **Tests** live in [test/](../../../test/) as `.bats` files (bats-core). Run `bats test/`. `test_helper.bash` sets up a temp `$HOME`.
- **Pre-commit hook** at `.githooks/pre-commit` runs gitleaks. Never `--no-verify`.
- **Remote is Gitea**, not GitHub. `git push` goes to `gitea.stump.rocks/joestump/dotfiles`. There is no GitHub mirror.
- Commit messages: match the surrounding history (short subject, body if helpful). No emoji unless the surrounding history uses them.

## Things that look wrong but aren't

- `dot_zshrc` is verbatim what the OMZ installer generated. It carries `plugins=(git)`, `ZSH_THEME=robbyrussell` — untouched by design so OMZ never conflicts. The per-machine theme override in `~/.config/dotfiles/zsh-theme` (written by `theme`) is what actually picks the prompt.
- `Library/` is macOS-only (launchd LaunchAgents); `.config/systemd/` is Linux-only. Both are OS-gated in `.chezmoiignore`.
- `signal-mcp` external clone is Linux-only — macOS uses Joe's dev checkout at `~/src/signal-mcp`. Do not add a macOS branch.
- `.claude/settings.local.json` and `.claude/worktrees/` at the repo root are local-only (dot-prefix auto-ignored by chezmoi). Do not `dot_`-prefix them; they'd propagate.

## Escalation

If work here is **blocked** by something down/broken/stale (Vault Agent won't authenticate, Signal daemon dead, chezmoi apply loops, external clone unreachable), file an OMG proactively — dotfiles are OMG-scoped per `~/.claude/CLAUDE.md`. Propose title + severity + one-line root cause to Joe first, then use the `stumpcloud-omg` skill.
