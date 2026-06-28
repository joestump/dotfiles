#!/usr/bin/env bash
# Shared helpers for the Claude MCP merge scripts. NO secrets here — only logic.
# Sourced by .chezmoiscripts/run_onchange_after_claude-*-mcp-merge.sh.

# mcp_secret <openbao-subpath> <field> <live-fallback>
#   OpenBao is authoritative; fall back to the live value if OpenBao is empty/unreachable.
mcp_secret() {
  local v
  v="$(vault kv get -field="$2" "secret/personal/$1" 2>/dev/null || true)"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$3"
}

# mcp_base  — emit the shared non-secret server defs (._comment stripped).
mcp_base() { jq 'del(._comment)' "$HOME/.config/dotfiles/mcp-servers.json"; }

# mcp_merge <target-file> <desired-mcpServers-json>
#   Repo-authoritative: managed servers replace live ones; other servers + every
#   non-mcpServers key are preserved. Only .mcpServers is rewritten. Idempotent.
mcp_merge() {
  local cj="$1" desired="$2" tmp new_mcp orig_keys
  [ -f "$cj" ] || { echo "  $cj: not present, skipping"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "  jq required"; return 1; }

  new_mcp="$(jq --argjson d "$desired" '(.mcpServers // {}) + $d' "$cj")"
  if [ "$(jq -cS '.mcpServers // {}' "$cj")" = "$(jq -cnS --argjson m "$new_mcp" '$m')" ]; then
    echo "  $cj: mcpServers already current"; return 0
  fi

  orig_keys="$(jq -cS 'keys' "$cj")"
  tmp="$(mktemp)"
  jq --argjson m "$new_mcp" '.mcpServers = $m' "$cj" > "$tmp"
  # SAFETY: every original top-level key must survive (no nuking oauth/session/etc.)
  if ! jq -e -n --argjson o "$orig_keys" --slurpfile n <(jq -cS 'keys' "$tmp") '($o - $n[0]) | length == 0' >/dev/null; then
    echo "  $cj: ABORT — merge would drop top-level keys"; rm -f "$tmp"; return 1
  fi
  chmod 600 "$tmp" && mv "$tmp" "$cj"
  echo "  $cj: mcpServers updated"
}
