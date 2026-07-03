---
title: zsh-syntax-highlighting
---

# zsh-syntax-highlighting

Fish-style live highlighting of the command line as you type. Its real job is
**catching errors before Enter**: a command name in red means zsh can't find
it. Cloned as a chezmoi external into `~/.oh-my-zsh/custom/plugins/`.

| You see | It means |
|---|---|
| green command | resolves — binary, alias, function, or builtin |
| **red command** | typo / not installed — this *will* fail |
| underlined word | exists as a valid file path |
| yellow quotes | string literal (unclosed quotes stay obviously open) |

## Pro tips

- **Treat red as a pre-flight check.** `chezmoi`, `kubectl`, `terrafrom` —
  if it's still red when you finish the word, you've typo'd it or the
  brew install hasn't happened. Zero-cost dry run on every command.
- **The underline is a path validator**: type a filename argument and if it
  gains an underline, the file exists — no more `ls` just to double-check a
  path before `rm` or `mv`.
- Green also confirms an **alias or function** resolves — useful sanity
  check after editing `aliases.zsh` or re-running `chezmoi apply`.
- It highlights matched vs. unmatched quotes and brackets as you type —
  when a long one-liner looks wrong at the far end, the colors show where
  the quoting went sideways.
- **Load order is law**: it must be the last plugin in `plugins=(...)` in
  `dot_zshrc`, with one blessed exception — `history-substring-search`,
  whose README requires loading *after* syntax-highlighting. That's exactly
  the ordering committed there; don't "alphabetize" it.
