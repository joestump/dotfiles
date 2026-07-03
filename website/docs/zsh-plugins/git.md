---
title: git
---

# git

The OMZ git plugin defines ~200 aliases over the git CLI. You don't need them
all — these dozen cover the daily loop, log archaeology, and context-switching:

| Alias | Runs |
|---|---|
| `gst` | `git status` |
| `gaa` | `git add --all` |
| `gcmsg` | `git commit --message` |
| `gp` / `gl` | `git push` / `git pull` |
| `gco` / `gcb` | `git checkout` / `git checkout -b` |
| `gcm` | `git checkout $(git_main_branch)` |
| `gd` / `gds` | `git diff` / `git diff --staged` |
| `glol` | pretty one-line graph log |
| `gwip` / `gunwip` | snapshot / restore work-in-progress |
| `gsta` / `gstp` | `git stash push` / `git stash pop` |
| `gcp` | `git cherry-pick` |
| `gpsup` | `git push --set-upstream origin $(git_current_branch)` |

## Pro tips

- **The daily loop is four keystrokes deep**: `gst` → `gaa` → `gcmsg "..."` →
  `gp`. With agents committing in most repos, this is mostly for the manual
  touch-ups in between.
- **`gwip` before switching contexts** — it commits everything (including
  deletes) as `--wip-- [skip ci]`, no hooks, no GPG. `gunwip` later undoes it
  only if HEAD is actually a wip commit, so it's safe to fire blind.
- **`glol` for archaeology**: graph + relative dates + author, which makes
  agent-authored commits easy to spot. `glola` adds `--all` for every branch;
  `glods` swaps in short dates.
- **`gcm` respects the repo** — it resolves `main`/`master` per repo via
  `git_main_branch`, so it works across Gitea and GitHub clones alike.
- **`grhh` is `git reset --hard`** — it eats uncommitted work. `gsta` first
  costs nothing; `gstp` gets it back.
- **`gpf` is the safe force**: `--force-with-lease` (plus `--force-if-includes`
  on newer git). `gpf!` is the raw `--force` — mind the trailing `!`.
