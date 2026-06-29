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
- Secrets come from **OpenBao** at apply time — never committed. The merge reads each
  with `vault kv get secret/personal/<svc>` and writes it into that server's `env`
  block (e.g. `.karakeep.env.KARAKEEP_API_KEY`) — that env map is the process
  environment Claude hands the spawned server. Two exceptions: **gitea** inherits
  `GITEA_ACCESS_TOKEN` from the login shell (no token in the config at all), and
  **outline** bakes a static `Bearer` header (Claude can't expand `${VAR}` in http
  headers). See `mcp_secret` / `mcp_merge` in `mcp-merge-lib.sh`.

Servers: `chrome-devtools`, `gitea`, `github`, `karakeep`, `outline`, `signal`.

```bash
# add a server: edit the JSON + its OpenBao secret, then
chezmoi apply
```

### Signal (cross-platform, daemon-backed)

`signal` is the one server that isn't a plain entry in `mcp-servers.json` — its `uv`
path and env `PATH` differ by OS, so the merge scripts **inject** `.signal` from
chezmoi template values. It's a thin JSON-RPC client to a long-running **signal-cli
daemon** on `tcp 127.0.0.1:7583`, supervised per-OS:

- **macOS** — LaunchAgent `rocks.stump.signal-daemon`; `signal-cli` + `uv` via Homebrew.
- **Linux** — systemd `--user` unit `signal-daemon`; `chezmoi apply` provisions the
  JRE (apt), `uv` (astral installer), `signal-cli` (pinned release tarball →
  `~/.local/bin`), and clones the MCP repo to `~/src/signal-mcp` (a Linux-only
  external tracking the default branch).

**One-time per node:** signal-cli must be *linked* as a device — interactive, so
chezmoi can't do it. After `chezmoi apply`, run:

```bash
signal-link            # renders the device-link QR; scan from Signal → Linked Devices
```

That links the device and starts the daemon; the MCP connects on next Claude launch.
On a Linux node you don't log into often, keep the daemon alive across logout with
`sudo loginctl enable-linger $USER` (one-time, the only sudo step).

## Plugins

`~/.config/dotfiles/claude-plugins.tsv` lists every plugin; a `run_after_` script
(runs on every apply) ensures each is installed **and current**:

```
tobi/qmd                                       qmd@qmd
joestump/claude-plugin-sdd                     sdd@claude-plugin-sdd
joestump/claude-skills                         claude-skills@joestump
~/.config/claude-marketplaces/claude-personal  personal@claude-personal
```

GitHub marketplaces add by `owner/repo`. The **private Gitea** one
(`claude-personal`) can't be HTTP-fetched, so a chezmoi **external** clones it
locally (refreshed every **24h**) and it's added as a **local-path** marketplace.

**Propagation:** local-path marketplaces (`claude-personal`) **auto-reinstall**
when the clone's git HEAD moves — so newly-pushed skills appear without bumping
the plugin `version` (which `claude plugin update` otherwise requires, and which
is easy to forget). The last-installed HEAD is tracked per plugin in
`~/.config/dotfiles/.claude-plugin-state/`. For an immediate pull + propagate:

```bash
chezmoi apply --refresh-externals
```

Remote (GitHub) marketplaces are install-once. There is **no bulk update** — `claude
plugin update` requires a plugin argument in `<plugin>@<marketplace>` form, e.g.:

```bash
claude plugin update qmd@qmd
claude plugin update sdd@claude-plugin-sdd
claude plugin update claude-skills@joestump
```

In practice you rarely run these by hand: the `run_after_` script already updates
remote plugins and reinstalls the local-path one on every `chezmoi apply`.
