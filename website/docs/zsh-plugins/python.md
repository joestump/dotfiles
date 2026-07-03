---
title: python
---

# python

Small helpers for working in Python trees. Honest framing: `uv` (`uv run`,
`uv venv`) is the primary Python workflow here — signal-mcp runs via uv — so
this plugin earns its keep with the file-hygiene helpers, which are
interpreter-agnostic and work fine alongside uv.

| Command | Does |
|---|---|
| `pyclean` | delete `*.pyc`, `__pycache__`, `.mypy_cache`, `.pytest_cache` |
| `pyfind` | `find . -name "*.py"` |
| `pygrep` | `grep -nr --include="*.py"` |
| `pyserver` | `python3 -m http.server` |
| `mkv` / `vrun` | create / activate a venv |

## Pro tips

- **`pyclean` is the keeper.** Stale `__pycache__` and `.pytest_cache` cause
  the weirdest "but I changed that file" bugs; run it before filing any
  Python bug report. Takes a path argument (`pyclean ~/src/foo`).
- **`vrun` auto-detects `venv` and `.venv`** — so it activates environments
  created by `uv venv` too. But if the project is uv-managed, prefer
  `uv run <cmd>`: no activation state to forget about.
- **`mkv` uses `python3 -m venv`**, which is the slow path. For anything new,
  `uv venv` is functionally identical and near-instant; treat `mkv` as
  legacy comfort.
- **`pyserver 8080`** is still the fastest "share this directory over HTTP on
  the LAN" — handy for tossing a file to a utility node.
- **`pygrep TODO`** respects only `.py` files — quicker than remembering
  ripgrep type flags for a one-off, though `rg -t py` is the better habit.
