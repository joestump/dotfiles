---
title: docker
---

# docker

Short aliases for the docker CLI plus version-aware completion. With every
StumpCloud service running as a container, these are daily drivers — the
incident-triage set especially:

| Alias | Runs |
|---|---|
| `dps` / `dpsa` | `docker ps` / incl. stopped containers |
| `dlo` | `docker container logs` |
| `dxcit` | `docker container exec -it` (shell into a container) |
| `drs` | `docker container restart` |
| `dcin` | `docker container inspect` |
| `dsts` | `docker stats` |
| `dsprune` | `docker system prune` |
| `dipru` | `docker image prune -a` |

## Pro tips

- **Wedged-container triage in four aliases**: `dpsa` (is it running/restarting/
  exited?) → `dlo <name> --tail 100` (why?) → `dxcit <name> sh` (poke inside)
  → `drs <name>`. This is the OMG-response loop; `dcin <name>` when you need
  restart counts, OOM kills, or mount details.
- `dpsa` over `dps` during incidents — a crash-looping or exited container is
  invisible to plain `dps`, and "it's not in `docker ps`" *is* the diagnosis
  half the time.
- **Prune carefully on storage-constrained nodes**: `dsprune` is the safe
  default (stopped containers, dangling images, unused networks). `dipru`
  (`image prune -a`) also deletes every image not attached to a running
  container — fine, but the next `docker compose pull` re-downloads them.
  `dvprune` deletes unused *volumes*: on a Compose host that can be real data,
  so read its list before confirming.
- `dsts` is the "which container is eating the node" command — live CPU/memory
  per container, no setup.
- Completion tracks your Docker version: ≥23 uses `docker completion zsh`,
  regenerated in the background and cached in `$ZSH_CACHE_DIR/completions`.
