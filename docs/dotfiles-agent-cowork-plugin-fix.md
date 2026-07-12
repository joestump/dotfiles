# Task: Surface personal@claude-personal skills in Cowork slash typeahead

## Problem

The `personal@claude-personal` plugin (skills: signal-message, contact-lookup,
outline-edits, stumpcloud-omg) is installed in Claude Code CLI but does **not**
appear in the Cowork slash command typeahead. Claude Code CLI plugins and Cowork
plugins are loaded from different sources.

## What we know

**Cowork loads skills from:**
`/var/folders/sp/c7zh23mx3dq9b4lt6qrgs9r80000gn/T/claude-hostloop-plugins/<hash>/`

Only one plugin hash is present there: the pre-bundled `anthropic-skills` plugin
(confirmed via `.claude-plugin/plugin.json` → `"name": "anthropic-skills"`).

**Claude Code CLI plugins** are installed via `run_after_install-claude-plugins.sh.tmpl`
using `claude plugin install personal@claude-personal`. These land in Claude Code's
own plugin registry but are NOT surfaced to Cowork.

**The personal plugin lives at:**
`~/.config/claude-marketplaces/claude-personal` (chezmoi external, cloned from
`https://gitea.stump.rocks/joestump/claude-personal.git`, refreshed every 24h).

Its structure:
```
.claude-plugin/
  marketplace.json
  plugin.json          # name: "personal", version: "0.1.0"
skills/
  signal-message/SKILL.md
  contact-lookup/SKILL.md
  outline-edits/SKILL.md
  stumpcloud-omg/SKILL.md
```

**Claude Desktop config** is at:
`~/Library/Application Support/Claude/claude_desktop_config.json`
Already managed by chezmoi via `run_onchange_after_claude-desktop-mcp-merge.sh.tmpl`
(merges MCP servers). It may also accept a `plugins` key — this is the first thing
to check.

## Investigation steps

1. **Check Claude Desktop config for plugin support:**
   ```bash
   cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | jq 'keys'
   ```
   Look for any `plugins`, `installedPlugins`, or similar key.

2. **Check for a separate Desktop plugin registry file:**
   ```bash
   ls ~/Library/Application\ Support/Claude/
   find ~/Library/Application\ Support/Claude/ -name "*.json" | xargs grep -l plugin 2>/dev/null
   ```

3. **Check how the cowork-plugin-management plugin IS loaded** — it appears in
   Cowork but isn't in `claude-hostloop-plugins`. Its session path is:
   `~/Library/Application Support/Claude/local-agent-mode-sessions/*/rpm/plugin_0155zZVATbJU3jHUmPP9NvMC/`
   Understand how plugins end up in the `rpm/` path vs the `claude-hostloop-plugins/` path.

4. **Check if `claude plugin install` has a `--target desktop` flag or similar:**
   ```bash
   claude plugin install --help
   claude plugin --help
   ```

## Expected fix

Once you understand the Claude Desktop plugin registration mechanism, add it to chezmoi:

- If Desktop uses a JSON config key: extend `run_onchange_after_claude-desktop-mcp-merge.sh.tmpl`
  (or a new `run_onchange_after_claude-desktop-plugin-merge.sh.tmpl`) to inject the plugin.
- If Desktop has its own `claude plugin install` target: extend `run_after_install-claude-plugins.sh.tmpl`
  to also install for Desktop.
- If the fix requires copying plugin files into a specific directory: add a chezmoi
  script that symlinks or copies `~/.config/claude-marketplaces/claude-personal`
  into the right location after each `chezmoi apply`.

The goal: after `chezmoi apply`, `/signal-message`, `/contact-lookup`,
`/outline-edits`, and `/stumpcloud-omg` appear in Cowork's slash typeahead.

## Existing chezmoi plumbing to reference

- `dot_config/dotfiles/claude-plugins.tsv` — plugin manifest
- `.chezmoiscripts/run_after_install-claude-plugins.sh.tmpl` — Claude Code CLI installer
- `.chezmoiscripts/run_onchange_after_claude-desktop-mcp-merge.sh.tmpl` — Desktop MCP merger
- `.chezmoiexternal.toml` — clones `claude-personal` repo to `~/.config/claude-marketplaces/claude-personal`
