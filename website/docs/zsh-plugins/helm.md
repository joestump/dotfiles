---
title: helm
---

# helm

Completion plus five short aliases for Helm. Like the kubectl plugins, this is
for occasional/work k8s contexts — StumpCloud itself is Compose-only.

| Alias | Runs |
|---|---|
| `h` | `helm` |
| `hin` | `helm install` |
| `hup` | `helm upgrade` |
| `hun` | `helm uninstall` |
| `hse` | `helm search` |

## Pro tips

- **Completion is the real feature.** Helm's completion is expensive to
  generate, so the plugin caches it in `$ZSH_CACHE_DIR/completions/_helm` and
  regenerates in the background on subsequent shells — full release-name and
  chart completion with no startup cost. Stale after a helm upgrade? Delete
  the cache file and open a new shell.
- `hup --install` (i.e. `helm upgrade --install`) is the idempotent deploy —
  installs if absent, upgrades if present. Worth typing over bare `hin` almost
  always.
- `hse repo <term>` searches your added repos; `hse hub <term>` searches
  Artifact Hub — same alias, very different scope.
- Before any `hup` on a chart you didn't write, `h diff upgrade` (if the
  helm-diff plugin is installed) or at minimum `h get values <release>` tells
  you what you're about to clobber.
- Context safety applies doubly here: helm acts on whatever kubectl context is
  live, so check the kubectx prompt segment before `hun`.
