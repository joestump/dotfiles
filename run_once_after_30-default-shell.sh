#!/usr/bin/env bash
# Make zsh the login shell on this machine (idempotent, best-effort).
# chezmoi installs zsh + Oh My Zsh but cannot change your login shell from a
# file, so we do it here. Linux utility nodes have passwordless sudo; macOS
# usually already defaults to zsh (and may prompt — run the printed command if so).
set -euo pipefail

zsh_bin="$(command -v zsh || true)"
[ -n "$zsh_bin" ] || { echo "zsh not found; skipping default-shell"; exit 0; }

case "$(uname -s)" in
  Darwin) current="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')" ;;
  *)      current="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)" ;;
esac

[ "$current" = "$zsh_bin" ] && { echo "login shell already $zsh_bin"; exit 0; }

echo "==> setting login shell to $zsh_bin (was: ${current:-unknown})"
if ! grep -qxF "$zsh_bin" /etc/shells 2>/dev/null; then
  echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null 2>&1 || echo "WARN: could not add $zsh_bin to /etc/shells" >&2
fi
{ sudo chsh -s "$zsh_bin" "$USER" 2>/dev/null \
  || chsh -s "$zsh_bin" 2>/dev/null; } \
  || echo "WARN: couldn't change login shell automatically — run: chsh -s $zsh_bin" >&2
