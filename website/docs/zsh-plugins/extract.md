---
title: extract
---

# extract

One command — `extract` (alias `x`) — unpacks any archive format without you
remembering whether it's `tar xzf`, `tar xvjf`, `unzip`, or `7za x`. It
handles `tar.{gz,bz2,xz,zst,lz4,…}`, zip/jar/war/whl/apk/ipa, rar, 7z, deb,
rpm, cab, cpio, and more.

```console
$ x mystery-download.tar.zst
$ x *.zip            # takes multiple files in one go
```

## Pro tips

- **It always extracts into its own directory** named after the archive — no
  more tarbombs spraying 40 files into `~/Downloads`. If the archive contains
  a single top-level folder, it's collapsed so you don't get
  `foo/foo/` nesting.
- **`x -r archive.tgz`** removes the archive after a successful unpack —
  ideal for the weekly Downloads consolidation, where mixed
  `.zip`/`.tar.gz`/`.dmg`-adjacent debris shows up constantly. One loop,
  zero format-switching: `for f in *.zip *.tgz; do x -r $f; done`.
- **`x -t ~/Managed\ Files/Documents foo.zip`** extracts into a target
  directory instead of the cwd.
- Name collisions are handled: extracting `foo.zip` next to an existing
  `foo/` creates `foo-<rand>/` rather than overwriting.
- It automatically uses parallel decompressors (`pigz`, `pbzip2`, `pixz`)
  when installed — free speedup on big tarballs for the price of a brew
  install.
- Tab completion on `extract`/`x` only offers files it can actually unpack.
