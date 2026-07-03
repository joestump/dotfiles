---
sidebar_position: 4
title: sudo
---

# sudo

Press **ESC ESC** and the current command line gets `sudo ` prefixed. Press it
again to remove it. Works on three targets:

1. **The line you're typing** — realize halfway through that it needs root.
2. **An empty prompt** — pulls the *previous* command from history, sudo-ed.
   This is the killer one: `systemctl restart foo` → permission denied →
   ESC ESC ↵.
3. **A line already starting with `sudo`** — toggles it off.

## Pro tips

- It's smarter than a plain prefix: `EDITOR`-launching commands become
  `sudoedit` (e.g. `vim /etc/hosts` → `sudoedit /etc/hosts`), which is the safe
  way to root-edit files.
- Most useful on the **Linux utility nodes**, where package and systemd
  operations are constant; on macOS it earns its keep with `launchctl` and
  `/etc` edits.
- ESC ESC also works mid-history-browse — arrow up to an old command, ESC ESC,
  enter.
