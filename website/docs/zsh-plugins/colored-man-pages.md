---
title: colored-man-pages
---

# colored-man-pages

Man pages, but readable: headings and keywords in bold red, options and
literals underlined in green, standout text in yellow-on-blue. The plugin
wraps `man` with the right `LESS_TERMCAP_*` colors — no config, it just
works the next time you run `man tar`.

## Pro tips

- Colors make **scanning for a flag dramatically faster** — option names pop
  in green, so `man rsync` stops being a wall of gray.
- It's still `less` underneath, so all the pager muscle memory applies:
  `/pattern` to search, `n`/`N` to jump between hits, `g`/`G` for top and
  bottom.
- The `colored` function is exposed directly — wrap any other
  termcap-respecting pager-ish command with it if you find one.
- The palette lives in the `less_termcap` associative array and can be
  overridden *after* the plugin loads (e.g. in `$ZSH_CUSTOM`) if bold red
  headers clash with the Catppuccin Mocha palette:
  `less_termcap[md]="${fg_bold[blue]}"`.
- It also colorizes `dman`/`debman` (from debian-goodies) for reading Debian
  man pages on the Linux utility nodes.
