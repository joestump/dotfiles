---
sidebar_position: 4
title: Claude (MCP + Plugins)
---

# Claude — MCP servers & plugins

Both **Claude Code** (`~/.claude.json`) and **Claude Desktop** run the same MCP
server set, and the same plugins, all driven from chezmoi.

## MCP servers

One non-secret source of truth — `~/.config/dotfiles/mcp-servers.json` — is merged
into both apps by `run_onchange_after_claude-{code,desktop}-mcp-merge.sh`:

- **Repo-authoritative** for the managed servers; preserves every other top-level
  key (OAuth tokens, session state) and any hand-added servers.
- Only `.mcpServers` is rewritten; the merge **aborts** if any top-level key would
  drop.
- Per-app shape: Code uses `type` + the native `http` outline; Desktop omits `type`
  and uses the `mcp-remote` stdio bridge.
- Tokens (gitea/github/karakeep) come from **OpenBao** at apply time — never committed.

Servers: `chrome-devtools`, `gitea`, `github`, `karakeep`, `outline`, `signal`.

```bash
# add a server: edit the JSON + its OpenBao secret, then
chezmoi apply
```

## Plugins

`~/.config/dotfiles/claude-plugins.tsv` lists every plugin; one `run_onchange_`
script ensures each is installed:

```
tobi/qmd                                       qmd@qmd
joestump/claude-plugin-sdd                     sdd@claude-plugin-sdd
joestump/claude-skills                         claude-skills@joestump
~/.config/claude-marketplaces/claude-personal  personal@claude-personal
```

GitHub marketplaces add by `owner/repo`. The **private Gitea** one
(`claude-personal`) can't be HTTP-fetched, so a chezmoi **external** clones it
locally and it's added as a **local-path** marketplace (which also keeps it synced).

Keep plugins current with `claude plugin update`.
