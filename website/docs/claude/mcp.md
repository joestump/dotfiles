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
  servers (`outline`, `cairn`, `switchboard`) over native `http`; Desktop
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
| `aws` | AWS account access — the GA [AWS MCP Server](https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available/) | remote, via a local SigV4 stdio proxy | `uvx mcp-proxy-for-aws` | both |
| `cairn` | Cairn artifacts/trajectories (`$CAIRN_BASE_URL`) | `http` (Code) · `mcp-remote` (Desktop) | native / `npx mcp-remote` | both |
| `chrome-devtools` | Drive a local Chrome for DevTools/automation | stdio | `npx chrome-devtools-mcp` | both |
| `gitea` | Self-hosted Gitea API (`gitea.stump.rocks`) | stdio | `go run …/gitea-mcp` | both |
| `karakeep` | Karakeep bookmarks (`karakeep.stump.rocks`) | stdio | `npx @karakeep/mcp` | both |
| `outline` | Outline wiki (`outline.stump.rocks`) | `http` (Code) · `mcp-remote` (Desktop) | native / `npx mcp-remote` | both |
| `signal` | Signal send/receive/react | stdio | `uv run` → signal-cli daemon | both · [setup →](./signal) |
| `switchboard` | Durable webhook→todo queue (`$SWITCHBOARD_CLAUDE_CODE_URL`) | `http` | native | **Code only** |

:::note[No `github` server — use the `gh` CLI]
The hosted GitHub MCP (`api.githubcopilot.com`) was retired. Every GitHub
operation — repos, issues, PRs, releases, Actions, reviews — goes through
[`gh`](https://cli.github.com/) instead, which authenticates from the environment
(`GH_TOKEN`/`GITHUB_TOKEN`) and therefore works in headless and daemon-launched
sessions where an MCP OAuth flow can't run. `gh api` covers anything the
subcommands don't. The merge scripts actively **drop** a stale `github` entry from
`~/.claude.json`, so an old config self-heals on the next apply. `gitea` is a
separate, still-live MCP server for the self-hosted forge.
:::

### Where each token comes from

Five servers need a credential; each is sourced differently so **nothing secret is
ever written to the chezmoi repo**. `aws` is the exception that proves the rule —
it needs credentials but stores none, because it signs with SigV4 from the
standard boto chain (see below).

OpenBao credentials are written as **`secret/users/<you>/<category>:<FIELD>`** —
the KV path, then `:`, then the field (env-var) name. e.g.
`secret/users/<you>/karakeep:KARAKEEP_API_KEY`.

| Server | Credential | Source |
| --- | --- | --- |
| `karakeep` | `KARAKEEP_API_KEY` | `secret/users/<you>/karakeep:KARAKEEP_API_KEY`, baked into `env` |
| `gitea` | `GITEA_TOKEN` | **Not in the config** — gitea-mcp inherits it from the login shell (`env.zsh`, from `secret/users/<you>/gitea:GITEA_TOKEN`) |
| `outline` | `Authorization: Bearer …` | `secret/users/<you>/outline:OUTLINE_API_TOKEN`, via the Vault-Agent-rendered `secrets-static.env`, baked as a static header (Code can't expand `${VAR}` in HTTP headers) |
| `cairn` | `Authorization: Bearer …` | `secret/users/<you>/cairn:CAIRN_API_TOKEN`, baked as a static header — same reason as outline. The **endpoint** comes from OpenBao too (`CAIRN_BASE_URL`) |
| `switchboard` | `Authorization: Bearer …` | `secret/users/<you>/switchboard:SWITCHBOARD_CLAUDE_CODE_API_KEY`, baked as a static header. The endpoint is the per-client `SWITCHBOARD_CLAUDE_CODE_URL` from the same bag (full URL incl. the minted `/mcp/<client>` slug) |

### `aws` — the one with no token

The AWS MCP Server is **remote and managed by AWS**; `mcp-proxy-for-aws` is a
local stdio bridge that exists because the remote endpoint authenticates with
**IAM SigV4** rather than OAuth, which MCP clients cannot speak natively.

That means there is nothing to bake in and nothing to rotate here: it uses the
standard boto credential chain, so it picks up whatever is already in the
environment. Rotating the underlying key changes nothing in this repo.

:::tip[This used to be broken everywhere but an interactive shell]
`secrets-aws.env` is sourced by `00-secrets.zsh`, an Oh My Zsh custom file — so
it only ever reached **interactive zsh**. Claude Desktop (a GUI app) and every
harness-launched agent (systemd/launchd) got no AWS credentials at all and failed
on the first tool call. `~/.aws` wasn't a fallback either: the `[default]`
profile on the Mac held a dead 2025-era key, and a Linux agent box had no
`~/.aws` at all.

Fixed in `dotfiles#136` by giving the non-interactive contexts a credential
source they can actually read. Vault Agent now renders a second template,
`secrets-aws.credentials.ctmpl`, to `~/.config/aws/credentials` in INI form with
two profiles:

| Profile | From | For |
| --- | --- | --- |
| `[default]` | `secret/users/<you>/aws` | Joe's admin key — CLI use |
| `[agent-readonly]` | `secret/users/<you>/aws-readonly` | The read-only agent identity — MCP servers and harness-launched agents |

The server entry points `AWS_SHARED_CREDENTIALS_FILE` at that file and selects
the profile with `AWS_PROFILE`, so the boto chain resolves identically from a
login shell, from Claude Desktop, and from a systemd-supervised agent.

Note the shape of the guard in that template: it ranges the KV **metadata**
listing and only reads a bag that's actually present. A fixed `with secret` read
404-loops for a user without the bag *and* leaves a stale file in place; ranging
the metadata means such a user renders cleanly to an empty file.
:::

Two things worth knowing:

- **The version is pinned** (`mcp-proxy-for-aws==1.6.4`). An unpinned `uvx`
  resolves to whatever is newest at launch, which makes a config that is supposed
  to be reproducible depend on release timing. Bump it deliberately.
- **The two AWS entries are different servers.** `aws-knowledge` (Crush only,
  `knowledge-mcp.global.api.aws`) is public documentation and needs no auth.
  `aws` reaches your actual account — it exposes `aws___call_aws` and
  `aws___run_script`, so it can change real resources.

The endpoint region (`us-east-1`) is the *service's* and is independent of
`AWS_REGION` in `--metadata`, which is the region the tools operate **on**
(`us-west-2`, matching `~/.aws/config`).

Rotating any of these is just `vault kv put …` then `chezmoi apply` (the merge
re-reads OpenBao every run).

### Runtime dependencies

A server only connects if its launcher is present on the box:

| Server | Needs | Notes |
| --- | --- | --- |
| `chrome-devtools` | Node (`npx`) + Chrome | — |
| `gitea` | Go toolchain | `go run …@latest` recompiles (~12 s) on a cold cache and overruns Claude's startup window, so `go-tools.txt` warms the build cache (`go install gitea-mcp`) |
| `karakeep` | Node (`npx`) | `@karakeep/mcp` from npm — no container, no registry login |
| `outline` | Node (`npx`) | Desktop only (the bridge); Code is native HTTP |
| `cairn` | Node (`npx`) | Desktop only (the bridge); Code is native HTTP |
| `switchboard` | nothing local | Code only — native HTTP, no bridge |
| `signal` | signal-cli daemon + `uv` + `~/src/signal-mcp` | See **[Signal](./signal)** |

## Add or change a server

```bash
$EDITOR ~/src/dotfiles/dot_config/dotfiles/mcp-servers.json   # the non-secret defs
vault kv put secret/users/<you>/<svc> <FIELD>=…               # only if it needs a secret
chezmoi apply --source ~/src/dotfiles ~/.claude.json          # try it before merging
```

Reference a secret as `secret/users/<you>/<svc>:<FIELD>` — the KV path, a colon,
then the field name. Merge the change and `czu` to propagate it; the apply
re-merges **both** apps.

Then **restart Claude Code / Desktop** to reload. Check what's live with
`claude mcp list` (shows ✔ connected / ✘ failed per server).

Crush does **not** read this file — it has its own MCP block in `crush.json`.
See [Crush](./crush).

> **Four servers aren't in `mcp-servers.json`** — the merge scripts inject them
> because their shape varies per app or per OS: `outline`, `cairn` and
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
