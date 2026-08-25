---
sidebar_position: 6
title: Services & schedules
---

# Services & schedules

Every long-running or recurring job this repo installs, and how to control it.
The pattern is uniform: **`systemd --user` on Linux, a launchd LaunchAgent on
macOS**, both rendered from the same chezmoi source, both set up by a
`run_onchange_` script.

## Always-on services

| Service | systemd (Linux) | launchd (macOS) | What it does |
| --- | --- | --- | --- |
| **Vault Agent** | `vault-agent.service` | `rocks.stump.vault-agent` | Authenticates to OpenBao and renders every secret template every ~5 min |
| **signal-cli daemon** | `signal-daemon.service` | `rocks.stump.signal-daemon` | JSON-RPC on `127.0.0.1:7583`, multi-account mode; the Signal MCP is a thin client to it |
| **harness daemon** | `harness.service` | `rocks.stump.harness` | Supervises agent sessions and runs their cron schedules |

Both harness units load `~/.config/vault/secrets-static*.env` before exec, which
is how supervised agents get their secrets with no login shell in the loop.

```bash
vault-agent status      # or start / stop / restart / log / env
signal-daemon status    # or start / stop / restart / log
harness doctor          # config + daemon + per-harness health
```

## Timers

| Job | Every | What it does |
| --- | --- | --- |
| **czu** | 6 h | Full sync + apply + secrets refresh. Silent on success |
| **Vault Agent stale detector** | 15 min | Alerts the moment the agent can no longer authenticate |
| **qmd `~/src` re-index** | 1 day | Refreshes the per-repo markdown search index |

All three are `Persistent=true`, so a missed run (laptop asleep) fires on wake.

### czu

The scheduled `czu` runs the **same** `czu-run.zsh` as the interactive one — the
interactive wrapper only adds the `exec zsh` reload, which makes no sense
headless. It stays silent on success. A failed run sends **one** Signal
note-to-self (not one per retry), and another once it recovers; the state stamp
lives in `~/.cache/`.

### The stale-secret detector

Worth understanding, because it exists to close a genuinely invisible failure:
when the Vault Agent's token dies it logs 403s and backs off, but nothing reaches
you — and the already-rendered `secrets-*.env` files persist at their last-good
values. The outage stays invisible until some unrelated command fails, hours
later.

The detector runs every 15 minutes, pings Signal the moment the agent can no
longer authenticate, and warns **before** a `token_file` login expires. It is
transition-based: one alert going stale, one coming back — not one per tick.
State lives in `~/.config/vault/.stale-state`.

### qmd re-indexing

Indexes each **top-level repo** under `~/src` into its own
[qmd](https://github.com/tobil/qmd) collection, so agents can `qmd query -c <repo>`
per project. One implementation, `~/.config/dotfiles/qmd-index-src.zsh`, driven
four ways:

```bash
dot            # → "🔎 Re-index ~/src (qmd)"
status         # → the 🔎 row: collection count, doc total, embed state
chezmoi apply  # a run_onchange_after_ hook
# …and the daily timer
```

Directories with **no markdown** are skipped (no empty collections), and
re-indexing is idempotent — collections are refreshed incrementally, never
recreated, so a scheduled run overlapping a manual one is safe. The scheduled run
logs to `~/.cache/qmd-index-src.log`.

Only the BM25 keyword index is built automatically. The ~2 GB embedding models
are **opt-in** — exactly like the qmd install itself — so semantic search needs a
manual `qmd embed`. That's the "embed pending" note `status` shows.

## Scheduled agents

Three one-shot agent runs are fired by the **harness daemon's own cron**, not by
a system timer. They're gated on the `-agent` login suffix, so a human login
never renders them.

| Harness | Schedule | What it does |
| --- | --- | --- |
| `stumpcloud-sweep` | every 6 h | Root-causes anything degraded in StumpCloud; files OMGs at MEDIUM+ |
| `pr-sweep` | daily 09:30 (agent) · 15:30 (human) | PRs only — own PRs (feedback, fixes, merge) plus review/approval of the sibling identity’s. Runs under BOTH identities |
| `issue-sweep` | Mondays 07:00 | Issues only — evidence-based triage (close only what is provably done) plus `size/*` labelling |

Their instructions live in chezmoi-managed prompt files
(`~/.config/dotfiles/*.prompt.md`), so a prompt edit propagates on a normal `czu`
and re-fires the daemon reload. Details: [Harness](claude/harness).

## Externals refresh

chezmoi **externals** — cloned upstreams rather than rendered files — cover the
zsh themes and external plugins, the private `claude-personal` marketplace, the
Crush and harness source trees, `vim-plug`, and the Crush external skill repos.
They refresh on their own cadence (the marketplace every 24 h), or on demand:

```bash
czu --refresh-externals
```

Every git-repo external pulls `--ff-only --quiet`. The `--quiet` is what keeps
`czu`'s output clean; the `--ff-only` is why the `~/src/ansible` clone is
deliberately **not** an external — agents develop there, and an ff-only pull on a
work branch would abort the whole apply.
