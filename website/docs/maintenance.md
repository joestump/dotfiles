---
sidebar_position: 6
title: Maintenance
---

# Maintaining the setup

Everything below is "edit a managed file, `chezmoi apply`, push." Pull on other
machines with `chezmoi update`.

## Add a shell helper

```bash
$EDITOR ~/.oh-my-zsh/custom/my-helper.zsh     # one function per file; OMZ auto-loads
chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
chezmoi cd && git add -A && git commit -m "Add my-helper" && git push && exit
```

## Add a secret

```bash
vault kv put secret/users/<you>/myservice MY_TOKEN=…
vault-agent restart && exec zsh        # auto-discovered, no template edits
```

## Add a tool

```bash
chezmoi edit ~/.Brewfile               # (or ~/.config/dotfiles/apt-packages.txt)
chezmoi apply
```

## Add a Claude MCP server or plugin

Edit `~/.config/dotfiles/mcp-servers.json` (+ its OpenBao secret) or
`claude-plugins.tsv`, then `chezmoi apply`. Full reference:
[MCP servers](claude/mcp).

## Link Signal on a new node

`chezmoi apply` installs everything, but the device link is interactive:

```bash
signal-link        # scan the QR from Signal → Linked Devices
```

Details (daemon control, troubleshooting): [Signal](claude/signal).

## Add a prompt glyph

Edit `PROMPT_GLYPHS` in `~/.zshrc`. Awkward to type? Use the codepoint:
`$''` is a heart.

## Search `~/src` with qmd

If `~/src` exists, apply indexes each **top-level repo** into its own
[qmd](https://github.com/tobil/qmd) collection (named after the directory) for
local hybrid markdown search — so agents can `qmd query -c <repo>` per project.
The logic lives in one place, `~/.config/dotfiles/qmd-index-src.zsh`, and is driven
three ways:

```bash
dot           # → "🔎 Re-index ~/src (qmd)"  (re-run any time)
status        # → the 🔎 qmd row: collection count, doc total, embed state
chezmoi apply # runs the same indexer (a run_onchange_after_ hook)
```

Dirs with **no markdown** are skipped (no empty collections), and re-indexing is
idempotent — existing collections are refreshed incrementally, not recreated. Only
the BM25 (keyword) index is built automatically; the ~2GB embedding models are
**opt-in** (exactly like the qmd install), so semantic search needs a manual
`qmd embed` — that's the "embed pending" note the `status` panel shows.

## Update everything

> 💡 **One step: `czu`** — brings this machine fully current in a single command: it
> runs `chezmoi update` (git pull + apply), then `vault-agent restart` (re-render
> secrets from OpenBao **now** instead of waiting ~5 min), then `exec zsh` to reload
> the shell so new config + secrets take effect. Extra args pass straight through, so
> **`czu --refresh-externals`** also re-pulls themes, plugins, marketplaces, and the
> `signal-mcp` clone.
>
> Installing a *fresh* spoke instead? `czinit <host>` does the whole thing over SSH
> — see [Install a Spoke](install/nodes).
>
> `czu` also runs **on its own, every 6 hours** (launchd on macOS, a systemd --user
> timer on Linux) — every box stays current without you typing anything. It stays
> silent on success; a failed scheduled run sends a Signal note-to-self once (not
> every retry), and another once it recovers.

![czu bringing a machine fully up to date, with per-phase checked sections](/img/screenshots/czu.png)

Under the hood, or to run the pieces by hand:

```bash
chezmoi update                         # git pull + apply (re-runs changed run_onchange_ scripts)
chezmoi apply --refresh-externals      # also re-pull themes/plugins/marketplaces + signal-mcp
brew bundle --global                   # macOS tools
```

Claude **plugins** update themselves — the `run_after_` script reinstalls the
local-path marketplace and updates remotes on every apply. There's no bulk
`claude plugin update`; to force one by hand it's `claude plugin update
<plugin>@<marketplace>` (e.g. `qmd@qmd`). See [Plugins](claude/plugins).

## CI

Every push runs **Gitea Actions** (`.gitea/workflows/ci.yml`):

- **bats** — the BATS test suite.
- **lint** — shellcheck (incl. rendered `*.tmpl`), `zsh -n`, JSON, TOML, YAML, and
  a gitleaks secret scan.

Run the tests locally with `bats test/`. This docs site ships from a separate
`pages` workflow to [Garage Pages](https://joestump.pages.stump.rocks/dotfiles/).
