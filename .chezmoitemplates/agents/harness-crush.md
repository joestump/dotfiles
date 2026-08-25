{{- /*
  Harness overlay: Crush.

  ONLY genuine capability deltas belong here: tools this harness has that the
  others don't, and paths only it reads. Policy goes in agents/base.md. If this
  file grows past ~30 lines, something policy-shaped has leaked in.
*/ -}}
## Crush specifics

**This file is rendered.** Its source is `.chezmoitemplates/agents/base.md` (shared policy) plus `.chezmoitemplates/agents/harness-crush.md` (this section), composed by `dot_config/crush/CRUSH.md.tmpl`. Editing `~/.config/crush/CRUSH.md` directly is lost on the next apply.

**Skills** come from `options.skills_paths` in `dot_config/crush/crush.json.tmpl`, pruned via `disabled_skills` — a different mechanism from Claude Code's plugin marketplace. A skill added for Claude Code is **not** automatically available to you.

**Crush reads `AGENTS.md`, `CRUSH.md`, and `CLAUDE.md`** from its config dir and the working directory, concatenating all of them. A repo-local `AGENTS.md` therefore stacks on top of these rules rather than replacing them; if the two genuinely conflict, the repo-local file wins for that repo and you should say so out loud.

**Semantic search over the current repo: `semantic_index` then `semantic_search`.** You have a vector index the other harnesses reach through qmd — same idea, but scoped to the working directory and built on demand. Run `semantic_index` once when you land in an unfamiliar repo (it is incremental, so re-runs only pay for files that moved), then ask `semantic_search` the questions grep is bad at: *where is auth handled*, *what decides whether to retry*, *what consumes this event*. For an exact symbol or string literal, `grep` is still correct and much cheaper. Embeddings run on Joe's own GPU via the LiteLLM gateway, so indexing costs wall time and nothing else. They are absent from your palette only when the `embeddings` block is missing from `crush.json`, or when the local index store fails to open — a changed `dimension` demands a reindex, and `crush_info`'s `[semantic_index]` section tells you which. An unreachable gateway is **not** that case: the tools stay in your palette and `semantic_index` fails at call time with an HTTP error, which is worth reporting rather than routing around.

**Scheduling: use CronCreate, never bash sleep/wait loops.** Crush has native `CronCreate`, `CronList`, and `CronDelete` tools for deferred and recurring work. Use them instead of `bash` with `sleep`, `wait`, polling loops, or backgrounded timers. Cron tasks survive session restarts (with `durable: true`), fire at minute precision, and are inspectable via `CronList`. A bash sleep loop wastes context, dies with the session, and cannot be audited or cancelled cleanly.
