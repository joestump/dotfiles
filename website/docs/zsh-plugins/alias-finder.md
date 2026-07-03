---
sidebar_position: 5
title: alias-finder
---

# alias-finder

Every time you run a command the long way, this prints the shorter alias you
could have used:

```text
$ git status
gst='git status'
On branch main …
```

With ~15 alias-heavy plugins enabled (`git`, `docker`, `kubectl`, `brew`,
`terraform`, …) there are **hundreds** of aliases available. Nobody learns them
from a list; this teaches them at the exact moment they're relevant.

Configured in `dot_zshrc` via zstyles:

```zsh
zstyle ':omz:plugins:alias-finder' autoload yes   # run on every command
zstyle ':omz:plugins:alias-finder' longer yes     # also show longer-but-related aliases
zstyle ':omz:plugins:alias-finder' cheaper yes    # only suggest if actually shorter
```

## Pro tips

- Run it manually against any command with `alias-finder "docker compose up"`.
- The `cheaper` flag matters — without it the output gets noisy with aliases
  longer than what you typed.
- Once an alias has sunk in and the echo becomes noise, it stays useful for the
  *next* plugin's aliases — the git ones take a week, the kubectl ones a month.
- Pair with `acs` (from the OMZ `aliases` lib) to browse aliases by group when
  you want the full menu instead of drip-feeding.
