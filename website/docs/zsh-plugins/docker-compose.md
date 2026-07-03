---
title: docker-compose
---

# docker-compose

Aliases for Compose that auto-detect v1 vs v2: if a real `docker-compose`
binary exists they use it, otherwise everything maps to `docker compose`.
Since StumpCloud *is* Docker Compose stacks, this is the most-used plugin on
the list.

| Alias | Runs |
|---|---|
| `dcupd` | `up -d` |
| `dcupdb` | `up -d --build` |
| `dcdn` | `down` |
| `dcl` / `dclf` | `logs` / `logs -f` |
| `dclF` | `logs -f --tail 0` (follow, no backlog) |
| `dce` | `exec` |
| `dcps` | `ps` |
| `dcpull` | `pull` |
| `dcrestart` | `restart` |

## Pro tips

- **The deploy loop is three aliases**: `dcpull && dcupd` picks up new images
  (Compose only recreates changed services), `dclf <service>` to confirm a
  clean start. That's the standard StumpCloud stack update.
- **`dclF` is the incident alias**: `--tail 0` skips the backlog and shows
  only *new* lines — follow it in one pane while you `dce <service> sh` in
  another, and you see exactly what your poking causes. `dcl --tail=200
  <service>` when you do want recent history.
- `dcupd <service>` recreates just one service from the stack — no need to
  bounce a whole compose file to restart the one wedged container. `dcrestart
  <service>` is lighter still (no recreate, keeps the container).
- `dcdn` removes containers and networks but **not** named volumes — safe for
  stack surgery. It's `down -v` that destroys data, and there's deliberately
  no alias for it.
- All aliases resolve the compose file from the current directory, so `cd`
  into the stack dir first — or pass `dco -f <file> <cmd>` for one-offs
  (`dco` is the bare compose alias).
