---
title: pip
---

# pip

Aliases and completion for pip. Straight talk: `uv pip` does everything pip
does, 10-100x faster — this plugin is legacy comfort for the machines and
moments where plain pip is what's in front of you (system Python, someone
else's venv, a remote box).

| Alias | Runs |
|---|---|
| `pipi` / `pipun` | `pip install` / `pip uninstall` |
| `pipu` | `pip install --upgrade` |
| `pipreq` | `pip freeze > requirements.txt` |
| `pipir` | `pip install -r requirements.txt` |
| `pipgi` | `pip freeze \| grep` |
| `piplo` | `pip list -o` (outdated) |

## Pro tips

- **The invisible win is `noglob`.** The plugin aliases `pip` to
  `noglob pip3`, so `pip install requests[socks]` works without quoting —
  zsh would otherwise try to glob the brackets and fail.
- **`pipreq` + `pipir`** are the freeze/restore pair for snapshotting a venv
  before experimenting. In uv-managed projects, skip both:
  `uv pip compile` / `uv sync` do it with proper lockfiles.
- **`pipgi <name>`** answers "is this installed, and what version?" in one
  shot — faster than `pip show` when you only need the line.
- **`pipig joestump/repo`** installs straight from a GitHub repo
  (`pipigb` for a branch, `pipigp` for a PR) — genuinely useful for testing
  someone's unreleased fix.
- **`pipupall` upgrades every outdated package** in the active environment.
  Fine in a throwaway venv; never run it in anything with a pinned
  requirements file.
