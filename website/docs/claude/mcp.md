---
sidebar_position: 2
title: MCP servers
---

# MCP servers

One non-secret source of truth — `~/.config/dotfiles/mcp-servers.json` — is merged
into both apps by `run_onchange_after_claude-{code,desktop}-mcp-merge.sh`:

- **Repo-authoritative** for the managed servers; preserves every *other* top-level
  key (OAuth tokens, session state) and any hand-added servers. Only `.mcpServers`
  is rewritten, and the merge **aborts** if any top-level key would drop.
- **Per-app shape:** Code tags each server with `type` and uses the native `http`
  outline; Desktop omits `type` and reaches outline through the `mcp-remote` stdio
  bridge.
- **Secrets never land in the repo.** They're read from **OpenBao** at apply time
  and written into the spawned server's `env` block. See `mcp_secret` / `mcp_merge`
  in `~/.config/dotfiles/mcp-merge-lib.sh`.

## The servers

| Server | What it is | Transport | Launched by | OS |
| --- | --- | --- | --- | --- |
| `chrome-devtools` | Drive a local Chrome for DevTools/automation | stdio | `npx chrome-devtools-mcp` | both |
| `gitea` | Self-hosted Gitea API (`gitea.stump.rocks`) | stdio | `go run …/gitea-mcp` | both |
| `github` | GitHub API | stdio | `docker run …/github-mcp-server` | both · Docker |
| `karakeep` | Karakeep bookmarks (`karakeep.stump.rocks`) | stdio | `docker run …/karakeep-mcp` | both · Docker |
| `outline` | Outline wiki (`outline.stump.rocks`) | `http` (Code) · `mcp-remote` (Desktop) | native / `npx mcp-remote` | both |
| `signal` | Signal send/receive/react | stdio | `uv run` → signal-cli daemon | both · [setup →](./signal) |

### Where each token comes from

Four servers need a credential; each is sourced differently so **nothing secret is
ever written to the chezmoi repo**:

| Server | Credential | Source |
| --- | --- | --- |
| `github` | `GITHUB_PERSONAL_ACCESS_TOKEN` | OpenBao `secret/personal/github`, baked into `env` at apply |
| `karakeep` | `KARAKEEP_API_KEY` | OpenBao `secret/personal/karakeep`, baked into `env` |
| `gitea` | `GITEA_ACCESS_TOKEN` | **Not in the config** — gitea-mcp inherits it from the login shell (`env.zsh`, exported from OpenBao) |
| `outline` | `Authorization: Bearer …` | `OUTLINE_API_TOKEN` from the Vault-Agent-rendered `secrets-static.env`, baked as a static header (Code can't expand `${VAR}` in HTTP headers) |

Rotating any of these is just `vault kv put …` then `chezmoi apply` (the merge
re-reads OpenBao every run).

### Runtime dependencies

A server only connects if its launcher is present on the box:

| Server | Needs | Notes |
| --- | --- | --- |
| `chrome-devtools` | Node (`npx`) + Chrome | — |
| `gitea` | Go toolchain | `go run …@latest` recompiles (~12 s) on a cold cache and overruns Claude's startup window, so `go-tools.txt` warms the build cache (`go install gitea-mcp`) |
| `github` | Docker | Image is public (`ghcr.io/github/github-mcp-server`) |
| `karakeep` | Docker | Private image — `docker login gitea.stump.rocks`; on Linux the user must be in the `docker` group (`sudo usermod -aG docker $USER`) |
| `outline` | Node (`npx`) | Desktop only (the bridge); Code is native HTTP |
| `signal` | signal-cli daemon + `uv` + `~/src/signal-mcp` | See **[Signal](./signal)** |

## Add or change a server

```bash
chezmoi edit ~/.config/dotfiles/mcp-servers.json    # edit the non-secret defs
vault kv put secret/personal/<svc> <FIELD>=…        # only if it needs a secret
chezmoi apply                                        # re-merges BOTH apps
```

Then **restart Claude Code / Desktop** to reload. Check what's live with
`claude mcp list` (shows ✔ connected / ✘ failed per server).

> **`signal` is special** — its `uv` path and `env` `PATH` differ by OS, so it is
> **not** listed in `mcp-servers.json`. The merge scripts inject `.signal` from
> chezmoi template values instead. To change it, edit the merge scripts. Full story
> on the **[Signal](./signal)** page.

## Keeping it in sync

The merge scripts are `run_onchange_`: chezmoi embeds a hash of `mcp-servers.json`
(and the merge lib) in each script, so `chezmoi apply` only re-runs the merge when
those files actually change — but **tokens are re-read from OpenBao every time the
merge fires**, so a rotated secret propagates on the next apply that touches the
config. To force a re-merge after only a secret change, `chezmoi apply --force`.
