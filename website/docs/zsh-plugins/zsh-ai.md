---
title: zsh-ai
---

# zsh-ai

[zsh-ai](https://github.com/matheusml/zsh-ai) turns a comment into a command:
type `# describe what you want`, press Enter, and the generated command lands
in your prompt — ready to read, edit, then run. Here it's wired to the LiteLLM
gateway (https://litellm.stump.rocks) with `ZSH_AI_PROVIDER=openai` and model
`gpt-oss:120b`, so "OpenAI" requests never leave StumpCloud.

```bash
$ # show what is using port 3000
$ lsof -i :3000
```

## Pro tips

- **It never auto-runs anything** — the command is pushed into your prompt
  with `print -z`. Read it, tweak it, then Enter. Treat it like a suggestion
  from a fast intern.
- **Phrase the outcome, not the tool**: `# compose logs for gitea since an
  hour ago` beats `# docker command`. The plugin already sends context
  (project type, git state, OS), so "run tests" resolves per-directory.
- **`ZSH_AI_PROMPT_EXTEND` shapes the output**: the zshrc sets "Prefer rg over
  grep, fd over find, eza over ls, and bat over cat", so generated commands
  match the tools actually installed. Add house rules there, not in each
  prompt.
- **Switching backends is one export**: `ZSH_AI_PROVIDER=anthropic` (uses
  `ANTHROPIC_API_KEY`, default `claude-haiku-4-5`) or `ollama` for fully
  local. Set it before `oh-my-zsh.sh` sources, or it won't take.
- **Pasting a script that starts with `#`?** The comment hook will eat the
  first line. Disable it with `ZSH_AI_COMMENT_HOOK=false` or change the
  trigger via `ZSH_AI_TRIGGER=",,"` — the `zsh-ai "..."` direct command still
  works either way.
