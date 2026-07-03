---
title: brew
---

# brew

Sets up Homebrew's environment (`brew shellenv`, sbin on PATH, completions)
and adds two-to-five-letter aliases for the whole `brew` surface. On this
setup Homebrew is Brewfile-driven: `~/.Brewfile` (source: `dot_Brewfile`) is
the single source of truth, installed by `brew bundle --global` — which
chezmoi runs automatically on `chezmoi apply`.

| Alias | Runs |
|---|---|
| `bi` / `bcin` | `brew install` / `brew install --cask` |
| `bubo` | `brew update && brew outdated` |
| `bubu` | `bubo` then `brew upgrade` |
| `bsl` / `bson` / `bsoff` | `brew services` list / start / stop |
| `bcn` | `brew cleanup` |

## Pro tips

- **Don't `bi` and walk away.** A bare `brew install` works today but never
  propagates to the other machines and won't survive a rebuild. Add a
  `brew "name"` line to `dot_Brewfile` in the chezmoi source, run
  `chezmoi apply`, done — that's the whole workflow.
- **`bubo` before `bubu`** — see what's outdated before upgrading. Blind
  `bubu` mid-week has shuffled tool versions under running work before;
  gitleaks in particular gates every commit, so if a hook starts failing
  after an upgrade, `brew bundle --global` restores the Brewfile world.
- **`brews`** (function, not alias) shows leaves with their dependents plus
  casks — the quickest "what did I actually ask for vs. what came along"
  audit, and a good diff against the Brewfile.
- **`ba`** (`brew autoremove`) after uninstalls keeps orphaned deps from
  accumulating; pair with `bcn` to reclaim disk.
- **`bsl`** is worth memorizing — launchd-managed services (databases,
  daemons) surface here, not in `ps`.
