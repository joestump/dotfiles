---
title: colorize
---

# colorize

Syntax-highlighted `cat` and `less`. The plugin provides `ccat`
(`colorize_cat`) and `cless` (`colorize_less`), backed here by
[chroma](https://github.com/alecthomas/chroma) — installed via the Brewfile,
which notes it's the conflict-free choice (single Go binary, no Python
`pygments` dependency chain).

| Command | Does |
|---|---|
| `ccat file.yaml` | syntax-highlighted cat |
| `cless script.py` | syntax-highlighted less |

## Pro tips

- **`ccat` is for eyeballing config files**: `ccat
  ~/.config/ghostty/config`, `ccat docker-compose.yml`. The lexer is guessed
  from the filename, and stdin works too (`curl -s $url | ccat`).
- **`cless` keeps highlighting while paging** — it wires `colorize_cat` in
  as a `LESSOPEN` preprocessor, so big files stream through `less -R`
  normally.
- The default style is `emacs`, which looks washed out on a dark background.
  Set `ZSH_COLORIZE_STYLE="catppuccin-mocha"` (chroma ships it) to match
  Ghostty.
- If colors look 8-bit, set
  `ZSH_COLORIZE_CHROMA_FORMATTER=terminal16m` for true-color output —
  Ghostty handles it fine; the default formatter is plain `terminal`.
- Note the tool-picking quirk: the plugin prefers `pygmentize` if it's ever
  installed. Pin `ZSH_COLORIZE_TOOL="chroma"` if a stray pip install starts
  changing your colors.
- Plain `cat` stays untouched — scripts and pipes keep byte-exact output,
  and the eza plugin already covers pretty listings.
