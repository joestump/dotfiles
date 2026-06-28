#!/usr/bin/env bash
# Install qmd's Claude Code plugin (preferred over a hand-written mcpServers entry).
# Stateful CLI mutation, gated on the plugin already being present.
set -euo pipefail

command -v claude >/dev/null 2>&1 || { echo "claude CLI absent; skipping qmd plugin"; exit 0; }
claude plugin list 2>/dev/null | grep -qi 'qmd' && { echo "qmd plugin present"; exit 0; }

claude plugin marketplace add tobi/qmd || true
claude plugin install qmd@qmd
echo "qmd Claude plugin installed."
