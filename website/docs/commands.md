---
sidebar_position: 2
title: Command reference
---

# Command reference

Every helper this repo puts on your `PATH`. They live one-function-per-file in
`~/.oh-my-zsh/custom/`, which Oh My Zsh auto-sources — there are no `source`
lines in `~/.zshrc`.

## The front door

| Command | What it does |
| --- | --- |
| `dot` | Interactive action hub — update, switch theme, status, re-index qmd, link Signal, restart a daemon, edit a config, open these docs |
| `status` | Health panel: Vault Agent, signal daemon, dotfiles drift, Claude skill freshness, qmd index, disk |
| `theme` | Pick a prompt theme; persisted **per machine** in `~/.config/dotfiles/zsh-theme`, so it survives `chezmoi apply` and can differ per box |

`dot` and `theme` need `gum` and a TTY; they print a clear message rather than
hanging when either is missing.

## Sync & bootstrap

| Command | What it does |
| --- | --- |
| `czu` | **Bring this machine fully current.** Syncs the production clone to `origin/main`, re-asserts app-rewritten targets, applies, restarts the Vault Agent, and `exec zsh` |
| `czu --refresh-externals` | Same, but also re-pulls themes, plugins, marketplaces, and the crush/harness source clones |
| `czinit <user@host>` | Bootstrap a **fresh spoke** end-to-end over SSH — seed Gitea credentials, install chezmoi, `init --apply`, provision the AppRole, clean up the bootstrap credential |
| `czapprole <user@host>` / `czapprole --local` | (Re-)provision a host's Vault Agent AppRole identity so it renews itself forever |
| `czrefresh` | Legacy `token_file` hosts: re-auth to OpenBao **and** re-render. On AppRole hosts it just forces a render |
| `reset` | A *full* reset — reinitialises the terminal, then runs `czu` |

`czu` also runs **on its own every 6 hours** (launchd on macOS, a `systemd --user`
timer on Linux). It's silent on success; a failed scheduled run sends one Signal
note-to-self, and another when it recovers. See [Services](services).

## Secrets

| Command | What it does |
| --- | --- |
| `vault-agent {start\|stop\|restart\|status\|log\|env}` | Control the Vault Agent service and inspect what it rendered |
| `vsr` | **Vault secrets refresh** — re-render *now* (skipping the ~5 min interval), wait for the file to actually change, then reload the shell |
| `vault-login [-r <role>] <host>` | From your laptop: open the OIDC callback tunnel to a remote host **and** log in there |
| `vault-oidc-login [role]` | The remote-side half — OIDC login on the box you're on. Without a role you land on `self-service` |

Without `-r`, you get the mount's `default_role` (`self-service` — CRUD on your
own `secret/users/<you>/*` and nothing else). Admin work needs `-r admin`, gated
on Pocket ID `admins` group membership.

Full picture: [Secrets](secrets).

## Signal

| Command | What it does |
| --- | --- |
| `signal-daemon {start\|stop\|restart\|status\|log\|ping}` | Control the `signal-cli` daemon (multi-account mode, JSON-RPC on `127.0.0.1:7583`). `ping` checks the port is listening |
| `signal-link` | Print a terminal QR to link this box as a new Signal device |

Details: [Signal](claude/signal).

## Agents

| Command | What it does |
| --- | --- |
| `harness` | The supervisor TUI + CLI — `harness list`, `start`, `stop`, `logs`, `attach`, `use-profile`, `reload`, `doctor` |
| `crush` | Joe's Crush fork, built from source into `~/.local/bin` |
| `claude` | Claude Code, via the `~/.local/bin/claude` version shim |

Details: [Harness](claude/harness) · [Crush](claude/crush).

## Odds and ends

| Command | What it does |
| --- | --- |
| `motd` | Re-print the StumpCloud login banner (host facts + the vault lock) |
| `flush-dns` | Flush the OS resolver cache |
| `qmd query -c <repo> …` | Search the per-repo markdown index of `~/src` — see [Maintenance](maintenance#search-src-with-qmd) |
| `cgg` | Call-graph CLI (Rust, installed from source) |

## chezmoi itself

:::warning
`chezmoi edit` and `chezmoi cd` operate on the **production** clone, which is
reset to upstream `main` on every `czu`. Don't use them to make changes — see
[Editing](workflow).
:::

| Command | Safe? | Notes |
| --- | :---: | --- |
| `chezmoi diff` | ✅ | What would change on this box |
| `chezmoi status` | ✅ | Pending targets. `--exclude=scripts` for genuine *file* drift |
| `chezmoi managed --include=files` | ✅ | Every target this repo owns |
| `chezmoi source-path <target>` | ✅ | Map a live file back to its source |
| `chezmoi apply --source ~/src/dotfiles <target>` | ✅ | Try a workbench change before it merges |
| `chezmoi edit` / `chezmoi cd` / `chezmoi add` | ❌ | All operate on production |
