---
title: virtualenv
---

# virtualenv

The smallest plugin in the roster: one function and one export. It provides
`virtualenv_prompt_info` for themes to display the active venv, and sets
`VIRTUAL_ENV_DISABLE_PROMPT=1` so activate scripts stop scribbling
`(venv)` onto the prompt themselves.

## Pro tips

- **The export is the real feature.** Without
  `VIRTUAL_ENV_DISABLE_PROMPT=1`, every `bin/activate` prepends its own
  `(venv)` marker, which stacks on top of whatever the theme draws. With
  this plugin loaded, the prompt has exactly one venv indicator — the
  theme's.
- **Spaceship already has a venv section**, so on this setup the indicator
  you see comes from spaceship reading `$VIRTUAL_ENV`, not from
  `virtualenv_prompt_info`. The plugin's job here is purely suppressing the
  duplicate.
- **It works with `uv venv` environments** — activation still sets
  `$VIRTUAL_ENV`, which is all the function and spaceship look at. If the
  prompt shows a generic `venv`/`.venv` name, that's the directory name;
  `uv venv --prompt myproj` (or `python -m venv --prompt`) sets
  `$VIRTUAL_ENV_PROMPT`, which this function prefers.
- **No indicator at all with `uv run`** — that's expected and fine. `uv run`
  never activates anything in your shell, so there is no state for a prompt
  to warn you about. The indicator only matters when you `source
  .venv/bin/activate` (or `vrun`) and might forget you did.
