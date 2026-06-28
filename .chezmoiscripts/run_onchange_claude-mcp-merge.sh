#!/usr/bin/env bash
# Repo-authoritative merge of the declarative mcpServers block into ~/.claude.json.
# - Only the .mcpServers key is rewritten; ALL other top-level keys (oauthAccount,
#   projects, session/cache state) are preserved untouched.
# - Managed servers (below) are authoritative: their definitions replace the live
#   ones. Any OTHER mcpServers you've added by hand are carried forward.
# - NO secrets in this script. gitea's token comes from OpenBao at runtime, falling
#   back to whatever is already live (so we never blank it out).
set -euo pipefail

CJ="$HOME/.claude.json"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
[ -f "$CJ" ] || { echo "no ~/.claude.json yet; skipping"; exit 0; }

# gitea token: PRESERVE the live token (a secret key — never overwrite a working
# credential). Seed from OpenBao only when none exists locally (fresh machine).
LIVE_TOK="$(jq -r '.mcpServers.gitea.env.GITEA_ACCESS_TOKEN // ""' "$CJ")"
if [ -n "$LIVE_TOK" ]; then
  TOK="$LIVE_TOK"
else
  TOK="$(vault kv get -field=GITEA_TOKEN secret/personal/gitea 2>/dev/null || true)"
fi

desired="$(jq -n --arg host "https://gitea.stump.rocks" --arg tok "$TOK" '{
  "chrome-devtools": { type:"stdio", command:"npx", args:["chrome-devtools-mcp@latest"], env:{} },
  "outline":         { type:"http", url:"https://outline.stump.rocks/mcp" },
  "gitea":           { type:"stdio", command:"go",
                       args:["run","gitea.com/gitea/gitea-mcp@latest","-t","stdio"],
                       env: ({ GITEA_HOST:$host } + (if $tok=="" then {} else { GITEA_ACCESS_TOKEN:$tok } end)) }
}')"

# '+' = shallow merge: managed servers replace live ones (authoritative); other
# servers preserved. Compute the new block and bail if nothing actually changes.
new_mcp="$(jq --argjson d "$desired" '(.mcpServers // {}) + $d' "$CJ")"
if [ "$(jq -cS '.mcpServers // {}' "$CJ")" = "$(jq -cnS --argjson m "$new_mcp" '$m')" ]; then
  echo "mcpServers already authoritative; nothing to do"; exit 0
fi

tmp="$(mktemp)"
jq --argjson m "$new_mcp" '.mcpServers = $m' "$CJ" > "$tmp"
# sanity: we must NOT have nuked session state
jq -e 'has("oauthAccount") and has("projects")' "$tmp" >/dev/null
chmod 600 "$tmp" && mv "$tmp" "$CJ"
echo "mcpServers updated (repo-authoritative; tokens + other top-level keys preserved)."
