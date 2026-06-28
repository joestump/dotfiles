#!/usr/bin/env bash
# Install the claude-plugin-sdd plugin (joestump/claude-plugin-sdd).
# Stateful CLI mutation, gated on the plugin already being present.
set -euo pipefail

command -v claude >/dev/null 2>&1 || { echo "claude CLI absent; skipping sdd plugin"; exit 0; }
claude plugin list 2>/dev/null | grep -qi 'sdd@claude-plugin-sdd' && { echo "sdd plugin present"; exit 0; }

claude plugin marketplace add joestump/claude-plugin-sdd || true
claude plugin install sdd@claude-plugin-sdd
echo "sdd Claude plugin installed."
