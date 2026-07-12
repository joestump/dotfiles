#!/usr/bin/env bash
# chezmoi run_once_ script: runs ONCE per machine, BEFORE chezmoi writes files.
# Only does what's needed to get a package manager + Oh My Zsh in place.
#   - macOS  -> Homebrew
#   - Linux  -> apt ONLY (no Homebrew)
# Idempotent: every step checks first.
set -euo pipefail

# Print the installed Node major version, or nothing if node is absent. The
# `command -v` guard matters: without it, a nodeless box runs `node -v`, which
# exits 127, and under `set -euo pipefail` that 127 propagates through the pipe
# and aborts the WHOLE script here — before Oh My Zsh and the dotfiles are ever
# written, leaving the box with no ~/.zshrc. The guard returns cleanly instead.
detect_node_major() {
  command -v node >/dev/null 2>&1 || return 0
  node -v | sed 's/^v//; s/\..*//'
}

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

  # ---- Node 22 (qmd needs >= 22; Ubuntu ships an older nodejs) ----
  # Runs here in the BEFORE phase so Node is present before run_onchange_after_16-install-qmd.
  # NON-FATAL: Node is only needed by qmd (which skips cleanly without it). A
  # transient NodeSource/apt hiccup must NOT abort the whole bootstrap and leave the
  # box with no ~/.zshrc — so warn-and-continue rather than die under `set -e`.
  node_major="$(detect_node_major)"
  if [ -z "$node_major" ] || [ "$node_major" -lt 22 ]; then
    echo "Installing Node 22 (NodeSource); have: $(node -v 2>/dev/null || echo none)"
    if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -; then
      sudo apt-get install -y nodejs || echo "WARN: nodejs install failed — qmd will skip; re-run 'czu' later."
    else
      echo "WARN: NodeSource setup failed — qmd will skip; re-run 'czu' later."
    fi
  fi
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
