---
title: zoxide
---

# zoxide

[zoxide](https://github.com/ajeetdsouza/zoxide) is a smarter `cd` that ranks
every directory you visit by *frecency* (frequency + recency). The OMZ plugin
just runs `zoxide init --cmd z zsh`, giving you `z` and `zi`. Binary from the
Brewfile (`brew "zoxide"`).

| Command | Does |
|---|---|
| `z chez` | jump to `~/.local/share/chezmoi` |
| `z <a> <b>` | multiple fragments must all match, in order |
| `z -` | previous directory (like `cd -`) |
| `zi <frag>` | interactive picker (fzf) when the fragment is ambiguous |

## Pro tips

- **Stop typing paths.** After a day of normal use, `z chez`, `z src`,
  `z managed` land in `~/.local/share/chezmoi`, `~/src/*`, and
  `~/Managed Files` from anywhere. The fragment matches anywhere in the path.
- **Ambiguous fragment? `zi`** pops an fzf picker over the ranked candidates
  — perfect for `~/src` where a dozen repos share substrings.
- `z foo<Space><Tab>` completes interactively too — same picker, without
  committing to the jump first.
- It only knows directories you've *visited*, so it gets better the longer
  you use it. Seed it with `zoxide add <dir>` if you want a path ranked
  before you've been there.
- This replaces the old OMZ `z` plugin (shell-script frecency) with a Rust
  implementation — same muscle memory, faster, and `zi` is the upgrade the
  old one never had.
- Plain `cd` still works and still feeds the database — every `cd`, `z`, and
  Alt+C (fzf) visit trains the ranking.
