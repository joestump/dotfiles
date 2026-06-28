---
sidebar_position: 3
title: Packages & Tooling
---

# Packages & Tooling

Tooling is declarative: add a line to a manifest, `chezmoi apply`, done. The
manifests are managed; `run_onchange_` scripts install from them (re-running only
when a manifest changes, via an embedded hash).

## macOS — the Brewfile

`~/.Brewfile` is the source of truth, installed with `brew bundle --global`:

```ruby
brew "chezmoi"
brew "direnv"
brew "gitleaks"
brew "fzf"
brew "zoxide"
brew "jq"
brew "gh"
brew "tea"               # Gitea CLI
cask "font-meslo-lg-nerd-font" if OS.mac?
```

```bash
chezmoi edit ~/.Brewfile      # add a line
chezmoi apply                 # installs it
```

`cask` lines are macOS-only (guarded with `if OS.mac?`). **`vault`** is installed
by an OS-aware step (HashiCorp tap on mac, apt repo on Linux), not the Brewfile, to
dodge tap-trust friction.

## Linux — apt

No Homebrew on nodes. The counterpart list is `~/.config/dotfiles/apt-packages.txt`:

```
zsh
git
fzf
zoxide
direnv
bats
```

`gh` and `vault` come from their official apt repos.

## Go tools

`~/.config/dotfiles/go-tools.txt` lists `go install` targets, installed when `go`
is present. `~/go/bin` is on `PATH` (and `~/.cargo/bin` for Rust tools like `cgg`).

## cgg (Rust)

Installed from source — the bootstrap installs Rust the platform-native way (brew
`rustup` on macOS, apt on Linux), then `cargo install --git`. Never `curl | sh`.
