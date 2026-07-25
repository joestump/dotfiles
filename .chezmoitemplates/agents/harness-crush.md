{{- /*
  Harness overlay: Crush.

  ONLY genuine capability deltas belong here: tools this harness has that the
  others don't, and paths only it reads. Policy goes in agents/base.md. If this
  file grows past ~30 lines, something policy-shaped has leaked in.
*/ -}}
## Crush specifics

**This file is rendered.** Its source is `.chezmoitemplates/agents/base.md` (shared policy) plus `.chezmoitemplates/agents/harness-crush.md` (this section), composed by `dot_config/crush/CRUSH.md.tmpl`. Editing `~/.config/crush/CRUSH.md` directly is lost on the next apply.

**Skills** come from `options.skills_paths` in `dot_config/crush/crush.json.tmpl`, pruned via `disabled_skills` — a different mechanism from Claude Code's plugin marketplace. A skill added for Claude Code is **not** automatically available to you.

**You have no scheduled-tasks MCP.** If a job needs to run on a timer, say so rather than improvising a loop — that work belongs to Claude Code, or to a systemd timer in the dotfiles.

**Crush reads `AGENTS.md`, `CRUSH.md`, and `CLAUDE.md`** from its config dir and the working directory, concatenating all of them. A repo-local `AGENTS.md` therefore stacks on top of these rules rather than replacing them; if the two genuinely conflict, the repo-local file wins for that repo and you should say so out loud.
