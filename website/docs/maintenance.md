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
vault kv put secret/personal/myservice MY_TOKEN=…
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

## Update everything

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
