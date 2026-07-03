---
sidebar_position: 6
title: copypath
---

# copypath

Copies an absolute path to the clipboard.

```text
$ copypath                    # copies $PWD
$ copypath dist/index.html    # copies /Users/joestump/…/dist/index.html
```

One command instead of `pwd | pbcopy` — and unlike `pwd | pbcopy`, it resolves
a relative argument to an absolute path first.

## Pro tips

- The everyday move: `copypath` in a deep directory, then paste into a Claude
  prompt, a Finder ⌘⇧G "Go to Folder" box, or an `scp` command on another tab.
- It works on files, not just directories — `copypath some.log` then paste into
  `tail -f ⌘V` elsewhere.
- Cross-platform: uses `pbcopy` on macOS and `xclip`/`wl-copy` on the Linux
  nodes, so the muscle memory transfers.
- Sibling plugin: [`copyfile`](copyfile.md) copies a file's *contents* instead
  of its path.
