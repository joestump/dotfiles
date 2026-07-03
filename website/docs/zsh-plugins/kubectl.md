---
title: kubectl
---

# kubectl

Completion plus ~100 `k`-prefixed aliases for kubectl. StumpCloud runs on
Compose, not k8s, so this earns its keep in work/client contexts — the
highest-value subset:

| Alias | Runs |
|---|---|
| `k` | `kubectl` |
| `kgp` / `kgpa` | get pods / across all namespaces |
| `klf` | `logs -f` |
| `keti` | `exec -t -i` (shell into a container) |
| `kdp` | `describe pods` |
| `kge` | events sorted by `.lastTimestamp` |
| `kaf` | `apply -f` |
| `kccc` / `kcuc` | current-context / use-context |
| `kcn` | set namespace on current context |
| `krrd` | `rollout restart deployment` |

## Pro tips

- **Completion is cached smartly**: the plugin regenerates
  `$ZSH_CACHE_DIR/completions/_kubectl` in the background on shell start, so
  you get full completion without paying the `kubectl completion zsh` startup
  tax every time. If completion goes stale after a kubectl upgrade, delete
  that file and open a new shell.
- The triage chain to memorize: `kgp` → `kdp <pod>` → `klf <pod>` → `keti
  <pod> -- sh`. Four aliases cover 90% of "why is this pod sad".
- `kge` sorts events by timestamp — genuinely more useful than default
  `get events` ordering when something just broke.
- `kca <anything>` runs any kubectl command with `--all-namespaces` bolted on.
- `kj get pod foo` pipes `-o json` through `jq`; `ky` does YAML through `yh` —
  both with completion intact.
