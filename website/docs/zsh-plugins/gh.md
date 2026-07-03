---
title: gh
---

# gh

Completion for the [GitHub CLI](https://cli.github.com/) — no aliases. On each
new shell it regenerates `gh completion --shell zsh` into `$ZSH_CACHE_DIR` in
the background, so completions always match the installed `gh` version.

## Pro tips

- **Tab through subcommands, flags, and even flag values** — `gh pr checkout
  <TAB>` won't complete PR numbers, but every subcommand and `--flag` does,
  which is where the muscle-memory savings are.
- **`gh pr checkout <number>`** is the fastest way to pull down an OSS
  contributor's PR for local review — it handles the fork remote and branch
  tracking for you.
- **`gh run watch`** live-tails a GitHub Actions run in the terminal; pair it
  with `gh run list` completion to grab the run. Beats refreshing the Actions
  tab while waiting on CI for OSS repos.
- **Scope check**: `gh` is for github.com work only. StumpCloud repos live on
  https://gitea.stump.rocks — use `tea` or the Gitea MCP there. If `gh` says
  "not a GitHub repository", you're probably standing in a Gitea-remoted
  clone.
- Completions also cover `gh api` paths and `gh extension` subcommands, so
  installed extensions get tab-completion automatically.
- If completion ever feels stale after a `brew upgrade gh`, just open a new
  shell — the plugin refreshes the cached script on load.
