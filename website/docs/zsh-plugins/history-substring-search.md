---
sidebar_position: 2
title: history-substring-search
---

# history-substring-search

Type any fragment of a command, then press **↑** — it cycles through every
history entry *containing* that fragment, not just prefix matches. The match is
highlighted inline.

```text
$ docker ↑        # walks docker run…, docker compose logs…, docker system prune…
$ stump ↑         # finds ssh stumpcloud, curl https://outline.stump.rocks/…
```

## Why it beats Ctrl+R

`fzf`'s Ctrl+R is still there for interactive fuzzy search across everything.
This plugin covers the *other* 90% case: you remember one word of the command
and just want to arrow through the hits without leaving the prompt line.

## Pro tips

- **Substring, not prefix** — `agent ↑` matches `launchctl kickstart -k gui/501/rocks.stump.vault-agent`. You never need to remember how a command *starts*.
- **↓ walks back** the other way if you overshoot.
- Matches are **deduplicated** — `HIST_FIND_NO_DUPS`-style behavior comes free, so hammering ↑ doesn't replay the same `git status` fifteen times.
- Case-insensitive matching: `set HISTORY_SUBSTRING_SEARCH_GLOBBING_FLAGS` is already `i` by default in the OMZ wrapper.
- Empty prompt + ↑ still behaves like plain history-walk, so muscle memory survives.

## Load-order footnote

This is the only plugin allowed to load *after* `zsh-syntax-highlighting` — its
README requires that ordering, which is why it sits in the final slot of
`plugins=(...)` in `dot_zshrc`.
