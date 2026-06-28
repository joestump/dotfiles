#!/usr/bin/env bash
# chezmoi run_once_ script: runs ONCE per machine, BEFORE chezmoi writes files.
# Only does what's needed to get a package manager + Oh My Zsh in place.
#   - macOS  -> Homebrew
#   - Linux  -> apt ONLY (no Homebrew)
# Idempotent: every step checks first.
set -euo pipefail

OS="$(uname -s)"
echo "==> dotfiles bootstrap: prerequisites ($OS)"

if [ "$OS" = "Darwin" ]; then
  # ---- macOS: Homebrew ----
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)" && break
  done

elif [ "$OS" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then
  # ---- Linux (Ubuntu/Debian): apt only. NO Homebrew. ----
  echo "Linux detected -> using apt (Homebrew is NOT installed on Linux)."
  sudo apt-get update -y
  sudo apt-get install -y zsh git curl ca-certificates gnupg
fi

# ---- ~/.ssh dir (the Vault Agent renders SSH keys into it) ----
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ---- Oh My Zsh (both OSes; never overwrite the chezmoi-managed ~/.zshrc) ----
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh (keeping chezmoi-managed .zshrc)..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> prerequisites ready"
