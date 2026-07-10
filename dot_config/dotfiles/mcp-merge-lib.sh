#!/usr/bin/env bash
# Shared helpers for the Claude MCP merge scripts. NO secrets here — only logic.
# Sourced by .chezmoiscripts/run_onchange_after_claude-*-mcp-merge.sh, AFTER they
# source ui-lib.sh — so status lines render as ticked items like every other phase.
# Fallbacks below keep the lib working if it's ever sourced without ui-lib.
command -v item >/dev/null 2>&1 || {
  item() { shift; echo "    - $*"; }
  warn() { echo "  WARN: $*" >&2; }
}

# mcp_secret <legacy-subpath> <env-var> <live-fallback>
#   Reads the per-user secret the Vault Agent injects into the shell env
#   (secret/users/$USER/* → ~/.config/vault/secrets-static.env) — the SAME pattern the
#   outline token uses in the code merge script. $2 is the env-var / KV field name; $1
#   (the old OpenBao subpath) is kept only for caller compatibility and is unused.
#   Falls back to the live value so a transient miss never blanks a working token.
#
#   Was: `vault kv get -field=$2 secret/personal/$1` — that queried the pre-per-user
#   SHARED path AND needed a live vault token at merge time; when none was present it
#   returned empty and blanked the outline/github/karakeep Bearers (dotfiles OMG,
#   2026-07-05). The env-injection path is per-user and needs no vault call.
mcp_secret() {
  local v
  v="$( . "$HOME/.config/vault/secrets-static.env" >/dev/null 2>&1; printf '%s' "${!2:-}" )"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$3"
}

# mcp_base  — emit the shared non-secret server defs (._comment stripped).
mcp_base() { jq 'del(._comment)' "$HOME/.config/dotfiles/mcp-servers.json"; }

# mcp_merge <target-file> <desired-mcpServers-json>
#   Repo-authoritative: managed servers replace live ones; other servers + every
#   non-mcpServers key are preserved. Only .mcpServers is rewritten. Idempotent.
mcp_merge() {
  local cj="$1" desired="$2" tmp new_mcp orig_keys
  [ -f "$cj" ] || { item dim "config not present — skipping"; return 0; }
  command -v jq >/dev/null 2>&1 || { warn "jq required"; return 1; }

  new_mcp="$(jq --argjson d "$desired" '(.mcpServers // {}) + $d' "$cj")"
  if [ "$(jq -cS '.mcpServers // {}' "$cj")" = "$(jq -cnS --argjson m "$new_mcp" '$m')" ]; then
    item dim "mcpServers already current"; return 0
  fi

  orig_keys="$(jq -cS 'keys' "$cj")"
  tmp="$(mktemp)"
  jq --argjson m "$new_mcp" '.mcpServers = $m' "$cj" > "$tmp"
  # SAFETY: every original top-level key must survive (no nuking oauth/session/etc.)
  if ! jq -e -n --argjson o "$orig_keys" --slurpfile n <(jq -cS 'keys' "$tmp") '($o - $n[0]) | length == 0' >/dev/null; then
    warn "ABORT — merge would drop top-level keys in $cj"; rm -f "$tmp"; return 1
  fi
  chmod 600 "$tmp" && mv "$tmp" "$cj"
  item ok "mcpServers updated"
}
