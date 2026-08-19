---
sidebar_position: 4
title: Packages & Tooling
---

# Packages & Tooling

Tooling is declarative: add a line to a manifest, merge, `czu`, done. The
manifests are chezmoi-managed; `run_onchange_` scripts install from them,
re-running only when a manifest changes (via a hash embedded in the script).

Every manifest below is edited in the **workbench** (`~/src/dotfiles`) — see
[Editing](workflow).

## macOS — the Brewfile

`~/.Brewfile` is the source of truth, installed with `brew bundle --global`.
It's split into three sections: what the dotfiles setup itself depends on,
everyday CLIs, and a commented-out "uncomment what you want" list.

```ruby
# Required by this setup
brew "chezmoi"
brew "direnv"
brew "gitleaks"
brew "fzf"
brew "zoxide"
brew "bats-core"      # test runner for this repo

# Everyday CLIs
brew "jq"             # JSON
brew "yq"             # YAML/JSON/XML
brew "gh"             # GitHub CLI
brew "tea"            # Gitea CLI
brew "gum"            # Charm TUI toolkit — powers dot / theme / status
brew "go"             # builds the Crush fork and the harness daemon
brew "uv"             # Python runner — launches the Signal MCP
brew "signal-cli"     # backs the Signal MCP daemon
brew "qrencode"       # terminal QR for `signal-link`
brew "chroma"         # backend for the colorize plugin
brew "figlet"         # the MOTD wordmark
brew "eza"            # modern ls — backend for the eza OMZ plugin
brew "tmux"           # optional backend= for harness-supervised agents

cask "font-meslo-lg-nerd-font" if OS.mac?
```

`cask` lines are macOS-only (guarded with `if OS.mac?`).

:::note[`vault` is deliberately not in the Brewfile]
The OpenBao-compatible client lives in `hashicorp/tap` on macOS and HashiCorp's
apt repo on Ubuntu, and is installed by an OS-aware step in the package script.
Keeping it out of the Brewfile dodges tap-trust friction so `brew bundle check`
stays clean.

And use **`vault`**, not `bao` — the Homebrew `bao` is an unrelated BLAKE3
hashing tool.
:::

## Linux — apt

No Homebrew on nodes. The counterpart list is
`~/.config/dotfiles/apt-packages.txt`; `gh` and `vault` come from their official
apt repos instead.

```
zsh git curl wget jq fzf zoxide direnv bats tmux
vim-gtk3                  # the fat vim build — headless vim is too minimal for vim-plug
figlet qrencode
openjdk-25-jre-headless   # JRE for signal-cli
python3-pygments          # `pygmentize`, backend for the colorize plugin
golang-go                 # Go toolchain — enables go-tools.txt
```

Two of those are load-bearing in non-obvious ways: signal-cli 0.14.5 needs
**Java 25** (class file 69) and throws `UnsupportedClassVersionError` on 21, and
Ubuntu's minimal `vim` build lacks the `+python3` vim-plug needs.

## Go tools

`~/.config/dotfiles/go-tools.txt` lists `go install` targets, installed whenever
`go` is present. `~/go/bin` is on `PATH`, and so is `~/.local/bin` — **ahead of
Homebrew**, which is how the locally-built Crush shadows any brew one.

| Tool | Why |
| --- | --- |
| `gitea.com/gitea/gitea-mcp` | Claude launches it with `go run …@latest`, which recompiles (~12 s) on a cold cache and overruns the MCP startup window. Installing it warms the build cache so `go run` starts instantly |
| `gitea.stump.rocks/stump.wtf/harness/cmd/harness` | The [harness daemon](claude/harness) — a fallback for boxes the from-source build hasn't reached |

## Built from source

Three things aren't packaged anywhere and are built on apply. All of them are
`run_after_` (every apply) but cheap — each fingerprints its own input and only
rebuilds when that moves.

| Tool | Source | Lands in |
| --- | --- | --- |
| **Crush** | The `~/.local/share/crush-src` external (Joe's fork — it keeps the upstream module path and ships no release binaries) | `~/.local/bin/crush` |
| **harness** | The `~/.local/share/harness-src` external | `~/.local/bin/harness` |
| **cgg** | `cargo install --git`; Rust comes from `rustup` (brew) or apt — never `curl \| sh` | `~/.cargo/bin` |

For an immediate pull + rebuild of any of them:

```bash
czu --refresh-externals
```

## Also installed

| Thing | How |
| --- | --- |
| **qmd** | Markdown search over `~/src` — see [Services](services#qmd-re-indexing) |
| **msgbrowse** | macOS only, from the `stump-wtf` Homebrew tap (CLI formula + desktop cask). The desktop app serves the local MCP endpoint the harness configs point at |
| **Ansible** | A `uv` venv at `~/.local/share/ansible-venv` plus the `~/src/ansible` clone. Deliberately **not** a chezmoi external — agents develop there, and an external's `--ff-only` pull aborts the whole apply when the checkout sits on a work branch |
| **vim-plug** | An external into `~/.vim/autoload/`, with plugin install on change |
