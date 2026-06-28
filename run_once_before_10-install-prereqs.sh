#!/usr/bin/env bash
# chezmoi run_once_ script: executes ONCE per machine (chezmoi tracks a hash),
# BEFORE chezmoi writes any dotfiles. This bootstraps a brand-new machine so a
# single `chezmoi init --apply <repo>` brings up the whole environment.
#
# Idempotent: every step checks before acting, so re-running is a no-op.
set -euo pipefail

echo "==> dotfiles bootstrap: prerequisites"

# ---- Homebrew ----
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Put brew on PATH for the remainder of this script (Apple Silicon / Intel / Linux).
for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [ -x "$p" ] && eval "$("$p" shellenv)" && break
done

# ---- CLI tools this setup depends on ----
echo "Installing CLI tools via Homebrew..."
brew install chezmoi direnv gitleaks fzf zoxide

# ---- OpenBao (secrets) ----
command -v bao >/dev/null 2>&1 || brew install openbao || true

# ---- Oh My Zsh (must NOT overwrite ~/.zshrc — chezmoi owns it) ----
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh (keeping chezmoi-managed .zshrc)..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> prerequisites ready"
