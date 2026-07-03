---
title: macos
---

# macos

A grab bag of Finder/terminal bridge functions for the Mac mothership. All
real shell functions, no daemons — most work via `osascript` under the hood.

| Command | Does |
|---|---|
| `ofd` | open current directory (or args) in Finder |
| `cdf` / `pushdf` | cd/pushd to the frontmost Finder window |
| `pfd` / `pfs` | print Finder's path / selected files |
| `quick-look <file>` | Quick Look without leaving the shell |
| `showfiles` / `hidefiles` | toggle hidden files in Finder |
| `rmdsstore` | delete `.DS_Store` recursively |
| `music <cmd>` | control Music.app (play, pause, vol, playlist…) |

## Pro tips

- **`cdf` and `ofd` are two halves of one bridge.** Finder window open on some
  buried folder → `cdf` puts the shell there. Shell in a deep repo path →
  `ofd` opens Finder on it. During the weekly `~/Managed Files/` sweep this
  pair kills all manual path-typing.
- **`pfs` pipes Finder selections into commands**: select files in Finder,
  then `pfs | xargs -I{} mv {} ~/Managed\ Files/Documents/` — batch triage
  without drag-and-drop.
- **`quick-look`** on a mystery download beats opening an app; space-bar
  preview, terminal never loses focus. Works on images, PDFs, video.
- **`tab`, `split_tab`, `vsplit_tab` know Ghostty** — they synthesize the
  right keystrokes for the frontmost terminal, so `tab 'npm start'` opens a
  new Ghostty tab already running the command in the same directory.
- **`rmdsstore`** before committing or rsyncing a directory tree; Finder
  litters `.DS_Store` everywhere it looks.
- **`music vol up`** / `music next` for keyboard-only Music.app control.
