#!/usr/bin/env bash
# chezmoi run_once_ script: runs AFTER apply. Wires the gitleaks pre-commit hook
# in the chezmoi source repo. `core.hooksPath` is local git config and is NOT
# carried by `git clone`, so a freshly-cloned dotfiles repo needs this set once.
set -euo pipefail

SRC="${HOME}/.local/share/chezmoi"
if [ -d "${SRC}/.git" ] && [ -d "${SRC}/.githooks" ]; then
  git -C "${SRC}" config core.hooksPath .githooks
  chmod +x "${SRC}/.githooks/pre-commit" 2>/dev/null || true
  echo "==> gitleaks pre-commit hook wired (core.hooksPath=.githooks)"
fi
