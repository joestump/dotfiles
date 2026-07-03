---
title: dirhistory
---

# dirhistory

Browser-style navigation for your shell's directory history. Every `cd` (and
`z` jump) is recorded; Alt+arrows walk the trail without touching the command
line.

| Key | Does |
|---|---|
| **Alt+←** | back — return to the previous directory |
| **Alt+→** | forward — undo an Alt+← |
| **Alt+↑** | up — `cd ..` |
| **Alt+↓** | down — into the first subdirectory (alphabetical) |

## Pro tips

- **Alt+← is the killer one**: `z` into a repo, check something, Alt+← puts
  you back where you were. Back/forward keep a 30-entry history
  (`DIRHISTORY_SIZE`), so you can walk several hops.
- These work in Ghostty because the plugin has explicit
  `TERM_PROGRAM=ghostty` bindings **and** `macos-option-as-alt = true` is
  already set in the Ghostty config — Option genuinely sends Alt. In other
  macOS terminals you'd get `¬` and friends instead.
- **Alt+↑ replaces typing `cd ..`** — and it stacks. Three quick presses from
  a deep `node_modules` hole beats counting `../../../`.
- The keys kill whatever's on the current line before switching directories,
  so don't hit them mid-command — the buffer is gone.
- It pairs with zoxide rather than competing: zoxide teleports across the
  filesystem, dirhistory retraces the steps you just took.
- The `cde` alias (`dirhistory_cd`) changes directory *without* clearing the
  forward stack — niche, but it's there.
