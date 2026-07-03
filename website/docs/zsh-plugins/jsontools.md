---
title: jsontools
---

# jsontools

Pipe-friendly JSON helpers for when full `jq` syntax is overkill. The plugin
picks the first available backend (node → python3 → ruby) at load time.

| Command | Does |
|---|---|
| `pp_json` | pretty-print JSON from stdin |
| `is_json` | prints `true`/`false`, exit code to match |
| `urlencode_json` | URL-encode stdin (for JSON in query strings) |
| `urldecode_json` | decode it back |

## Pro tips

- **`pp_json` is the zero-thought pretty-printer**: `curl -s
  https://api.example.com | pp_json`, `pbpaste | pp_json`, `pp_json <
  ~/.claude.json`. When you're debugging an MCP config blob and just need it
  readable, this beats remembering that the jq identity filter is `.`.
- **`is_json` is built for scripts and pipelines** — it sets the exit code,
  so `curl -s $url | is_json && echo ok` is a one-line sanity check on an
  API response before you feed it to something stricter.
- Each helper has an **NDJSON twin** (`pp_ndjson`, `is_ndjson`,
  `urlencode_ndjson`, `urldecode_ndjson`) that applies the function per line
  — handy for streaming logs and JSONL exports.
- These complement, not replace, the `jq`/`yq` pair from the Brewfile:
  reach for jsontools to *look at* JSON, reach for jq to *transform* it.
- Backend choice is overridable with `JSONTOOLS_METHOD=node|python3|ruby`.
  Quirk worth knowing: the ruby backend's `pp_json` emits YAML, which is
  occasionally exactly what you want.
