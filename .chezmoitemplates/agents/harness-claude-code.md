{{- /*
  Harness overlay: Claude Code (both the CLI and the copy embedded in Claude
  Desktop — they read the same ~/.claude/CLAUDE.md).

  ONLY genuine capability deltas belong here: tools this harness has that the
  others don't, and paths only it reads. Policy goes in agents/base.md. If this
  file grows past ~30 lines, something policy-shaped has leaked in.
*/ -}}
## Claude Code specifics

**This file is rendered.** Its source is `.chezmoitemplates/agents/base.md` (shared policy) plus `.chezmoitemplates/agents/harness-claude-code.md` (this section), composed by `dot_claude/CLAUDE.md.tmpl`. Editing `~/.claude/CLAUDE.md` directly is lost on the next apply.

**Skills and plugins** come from `dot_config/dotfiles/claude-plugins.tsv.tmpl`; local marketplaces are fingerprinted by clone HEAD under `~/.config/dotfiles/.claude-plugin-state/`. Crush discovers skills through a *separate* mechanism, so adding one here does not give it to Crush.

### Scheduled Tasks

You have the scheduled-tasks MCP; the other harnesses do not. Every scheduled task must send a Signal Note to Self summary to {{ .signalNumber }} (Joe's Signal note-to-self number — use the phone number, NOT the email, or the send fails) via `mcp__signal__send_message_to_user` when the run completes. Mandatory for all new scheduled tasks.

- Exception: skip when nothing happened (e.g. `NO_CHANGES` in gitea-claude-sync, no replies sent in message-auto-reply).
- Format: emoji + task name + date as the header line, then 1-3 key outcome lines.
- Formatting rules for the message itself are in the Signal section above.
