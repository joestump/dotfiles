---
sidebar_position: 7
title: copyfile
---

# copyfile

Copies a file's **contents** to the clipboard:

```text
$ copyfile ~/.config/vault/agent.hcl
```

No more `cat file` → mouse-select → ⌘C (which mangles long lines and picks up
prompt characters), and no more remembering `pbcopy < file`.

## Pro tips

- Perfect for pasting configs, logs, or snippets into chats and issue trackers
  — the paste is byte-exact, including trailing newlines.
- Combine with process substitution for command output:
  `copyfile <(chezmoi doctor)` works because it just reads a file descriptor.
- On Linux nodes it falls back to `xclip`/`xsel` the same way
  [`copypath`](copypath.md) does.
- If the file is secret-bearing, remember the clipboard is world-readable to
  local apps — fine on your own Macs, think twice on shared boxes.
