---
sidebar_position: 1
title: Overview
---

# Claude across every machine

Claude **Code** runs on the macOS mothership **and** every Linux utility node;
Claude **Desktop** runs on macOS. All of them pull the **same MCP servers and the
same plugins** from one chezmoi-managed source — edit a single file, `chezmoi
apply`, and every app on every box converges.

## What runs where

| App | macOS (mothership) | Linux (utility nodes) | Config file |
| --- | :---: | :---: | --- |
| **Claude Code** | ✓ | ✓ | `~/.claude.json` |
| **Claude Desktop** | ✓ | — *(no Linux build)* | `~/Library/Application Support/Claude/claude_desktop_config.json` |

## One source, every app

```
~/.config/dotfiles/mcp-servers.json    (non-secret server defs — the source)
~/.config/dotfiles/claude-plugins.tsv  (the plugin list)
        │   run_onchange_ merge scripts  +  OpenBao secrets (baked at apply)
        ▼
~/.claude.json              ~/Library/Application Support/Claude/…
(Code — macOS + Linux)      (Desktop — macOS)
```

The merge handles the things that *must* differ, so you don't have to:

- **Per app** — Code tags each server with `type` and talks to outline over native
  `http`; Desktop omits `type` and bridges outline through `npx mcp-remote`.
- **Per OS** — `signal`'s `uv` path and `PATH` differ macOS vs Linux; the merge
  injects the right ones for the box it's running on.

## "Same MCPs across the board" — with one honest caveat

The **config** is identical on every machine. Whether a given server actually
**connects** depends on its runtime being present there:

| Server | Connects where |
| --- | --- |
| `chrome-devtools`, `outline` | everywhere (Node) |
| `gitea` | everywhere (Go build cache is warmed by chezmoi) |
| `signal` | everywhere, once the node is device-linked → [Signal](./signal) |
| `github`, `karakeep` | anywhere Docker is available; on Linux the user must be in the `docker` group |

So the goal — *the same servers offered to Claude on every machine* — is met by the
config. The runtime deps (Docker, a Signal device link) are what you provision per
box.

→ **[MCP servers](./mcp)** · **[Plugins](./plugins)** · **[Signal](./signal)**
