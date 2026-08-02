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
- **Per-app shape:** Code tags each server with `type` and reaches the remote
  servers (`github`, `outline`, `cairn`, `switchboard`) over native `http`; Desktop
  omits `type` and reaches them through the `npx mcp-remote` stdio bridge.
- **No Docker.** Every server is a plain stdio launcher (`npx`/`go`) or a remote
  HTTP endpoint — nothing here needs a container runtime.
- **Secrets never land in the repo.** They're read from **OpenBao** at apply time
  and written into the spawned server's `env` block. See `mcp_secret` / `mcp_merge`
  in `~/.config/dotfiles/mcp-merge-lib.sh`.
- **Service base URLs come from OpenBao too** (`mcp_env`), not from the repo — so
  moving a service is one `vault kv put`, and Crush, Code and Desktop all follow.
  Switchboard's minted `/mcp/<client>` slug is a per-user credential-path, so it
  rides OpenBao as well, as a full per-client URL (`SWITCHBOARD_CRUSH_URL` /
  `SWITCHBOARD_CLAUDE_CODE_URL`) — committed data renders identically on every
  box, which is exactly what a per-identity value must never do.

## The servers

| Server | What it is | Transport | Launched by | OS |
| --- | --- | --- | --- | --- |
| `cairn` | Cairn artifacts/trajectories (`$CAIRN_BASE_URL`) | `http` (Code) · `mcp-remote` (Desktop) | native / `npx mcp-remote` | both |
| `chrome-devtools` | Drive a local Chrome for DevTools/automation | stdio | `npx chrome-devtools-mcp` | both |
| `gitea` | Self-hosted Gitea API (`gitea.stump.rocks`) | stdio | `go run …/gitea-mcp` | both |
| `github` | GitHub API (**remote hosted** MCP) | `http` (Code) · `mcp-remote` (Desktop) | `api.githubcopilot.com` | both |
| `karakeep` | Karakeep bookmarks (`karakeep.stump.rocks`) | stdio | `npx @karakeep/mcp` | both |
| `outline` | Outline wiki (`outline.stump.rocks`) | `http` (Code) · `mcp-remote` (Desktop) | native / `npx mcp-remote` | both |
| `signal` | Signal send/receive/react | stdio | `uv run` → signal-cli daemon | both · [setup →](./signal) |
| `switchboard` | Durable webhook→todo queue (`$SWITCHBOARD_CLAUDE_CODE_URL`) | `http` | native | **Code only** |

### Where each token comes from

Six servers need a credential; each is sourced differently so **nothing secret is
ever written to the chezmoi repo**:

OpenBao credentials are written as **`secret/users/<you>/<category>:<FIELD>`** —
the KV path, then `:`, then the field (env-var) name. e.g.
`secret/users/<you>/karakeep:KARAKEEP_API_KEY`.

| Server | Credential | Source |
| --- | --- | --- |
| `github` | `Authorization: Bearer …` | `secret/users/<you>/github:GITHUB_PERSONAL_ACCESS_TOKEN`, baked as a Bearer header — like outline |
| `karakeep` | `KARAKEEP_API_KEY` | `secret/users/<you>/karakeep:KARAKEEP_API_KEY`, baked into `env` |
| `gitea` | `GITEA_TOKEN` | **Not in the config** — gitea-mcp inherits it from the login shell (`env.zsh`, from `secret/users/<you>/gitea:GITEA_TOKEN`) |
| `outline` | `Authorization: Bearer …` | `secret/users/<you>/outline:OUTLINE_API_TOKEN`, via the Vault-Agent-rendered `secrets-static.env`, baked as a static header (Code can't expand `${VAR}` in HTTP headers) |
| `cairn` | `Authorization: Bearer …` | `secret/users/<you>/cairn:CAIRN_API_TOKEN`, baked as a static header — same reason as outline. The **endpoint** comes from OpenBao too (`CAIRN_BASE_URL`) |
| `switchboard` | `Authorization: Bearer …` | `secret/users/<you>/switchboard:SWITCHBOARD_CLAUDE_CODE_API_KEY`, baked as a static header. The endpoint is the per-client `SWITCHBOARD_CLAUDE_CODE_URL` from the same bag (full URL incl. the minted `/mcp/<client>` slug) |

Rotating any of these is just `vault kv put …` then `chezmoi apply` (the merge
re-reads OpenBao every run).

### Runtime dependencies

A server only connects if its launcher is present on the box:

| Server | Needs | Notes |
| --- | --- | --- |
| `chrome-devtools` | Node (`npx`) + Chrome | — |
| `gitea` | Go toolchain | `go run …@latest` recompiles (~12 s) on a cold cache and overruns Claude's startup window, so `go-tools.txt` warms the build cache (`go install gitea-mcp`) |
| `github` | nothing local | Remote hosted at `api.githubcopilot.com` — just the PAT Bearer (Desktop adds the `npx mcp-remote` bridge) |
| `karakeep` | Node (`npx`) | `@karakeep/mcp` from npm — no container, no registry login |
| `outline` | Node (`npx`) | Desktop only (the bridge); Code is native HTTP |
| `cairn` | Node (`npx`) | Desktop only (the bridge); Code is native HTTP |
| `switchboard` | nothing local | Code only — native HTTP, no bridge |
| `signal` | signal-cli daemon + `uv` + `~/src/signal-mcp` | See **[Signal](./signal)** |

## Add or change a server

```bash
chezmoi edit ~/.config/dotfiles/mcp-servers.json    # edit the non-secret defs
vault kv put secret/users/<you>/<svc> <FIELD>=…        # only if it needs a secret (ref it as secret/users/<you>/<svc>:<FIELD>)
chezmoi apply                                        # re-merges BOTH apps
```

Then **restart Claude Code / Desktop** to reload. Check what's live with
`claude mcp list` (shows ✔ connected / ✘ failed per server).

> **Five servers aren't in `mcp-servers.json`** — the merge scripts inject them
> because their shape varies per app or per OS: `github`, `outline`, `cairn` and
> `switchboard` are remote HTTP with a baked Bearer (native `http` for Code, `npx
> mcp-remote` for Desktop — except `switchboard`, which is Code-only), and
> `signal`'s `uv` path + `PATH` differ macOS vs Linux. To change those, edit the
> merge scripts (not the JSON). Full Signal story on the **[Signal](./signal)** page.

## Keeping it in sync

The merge scripts are `run_onchange_`: chezmoi embeds a hash of `mcp-servers.json`
(and the merge lib) in each script, so `chezmoi apply` only re-runs the merge when
those files actually change — but **tokens are re-read from OpenBao every time the
merge fires**, so a rotated secret propagates on the next apply that touches the
config. To force a re-merge after only a secret change, `chezmoi apply --force`.
