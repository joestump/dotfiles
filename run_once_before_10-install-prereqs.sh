#!/usr/bin/env bash
# chezmoi run_once_ script: executes ONCE per machine, BEFORE chezmoi writes any
# dotfiles. It only does what's needed to GET Homebrew + Oh My Zsh in place — the
# actual tool list lives in ~/.Brewfile and is installed by the run_once_AFTER
# package script (once chezmoi has written ~/.Brewfile).
#
# Cross-platform: macOS and Ubuntu/Linux. Idempotent (every step checks first).
set -euo pipefail

echo "==> dotfiles bootstrap: prerequisites ($(uname -s))"

# ---- Linux: install Homebrew's prerequisites via apt (Ubuntu: ie01/ie02) ----
if [ "$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew prerequisites via apt..."
    sudo apt-get update -y
    sudo apt-get install -y build-essential procps curl file git
  fi
fi

# ---- Homebrew (macOS + Linux) ----
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Put brew on PATH for the rest of this script (Apple Silicon / Intel / Linux).
for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [ -x "$p" ] && eval "$("$p" shellenv)" && break
done

# ---- Oh My Zsh (must NOT overwrite ~/.zshrc — chezmoi owns it). Installed here,
#      before chezmoi writes ~/.oh-my-zsh/custom/*, so the OMZ installer doesn't
#      bail on a pre-existing ~/.oh-my-zsh. ----
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh (keeping chezmoi-managed .zshrc)..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> prerequisites ready (tooling installs next, from ~/.Brewfile)"
