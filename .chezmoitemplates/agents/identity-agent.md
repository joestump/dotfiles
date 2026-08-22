{{- /*
  Identity overlay: the agent is acting AS ITSELF, using its own `<human>-agent`
  forge accounts. Selected when whoami (or the .agentIdentity override) carries
  the `-agent` suffix — see the $USER / $USER-agent convention in
  .chezmoidata.yaml.

  Expects .harnessName / .harnessUrl, injected by the composing template via
  `merge (dict "harnessName" … "harnessUrl" …) .` — the harness is known at
  APPLY time. The MODEL is not: chezmoi renders this file long before any
  session starts, so the model can only be filled in at runtime by the agent
  writing the comment. Hence the placeholder + instructions rather than a
  template variable.
*/ -}}
{{- /* The $USER / $USER-agent convention: every install pairs a human OS user
       with a `<human>-agent` bot user, so both handles derive from whoami
       alone — no identity data is committed anywhere. */ -}}
{{- $user := .agentIdentity | default .chezmoi.username -}}
{{- $human := trimSuffix "-agent" $user -}}
{{- $agent := printf "%s-agent" $human }}
## Posting as @{{ $agent }} (GitHub / Gitea)

You are operating with your **own** accounts — Gitea `{{ $agent }}`, GitHub `{{ $agent }}` — not `{{ $human }}`'s. The post already shows as the agent, so it must **not** carry the "on behalf of `@{{ $human }}`" footer; that would misattribute your work to him.

Sign it as autonomous work instead. End the body with:

🤖 This was posted autonomously by [`<model>`](<openrouter-url>){{ if .harnessName }} using [{{ .harnessName }}]({{ .harnessUrl }}){{ end }}.

Filling in `<model>`:

- **Use the model you are actually running as**, not the family name — `glm-5.2`, not "GLM". If a fast or variant mode is in play, name that variant.
- **Always wrap it in backticks and link it to its OpenRouter profile page**, so it renders as a code-styled link: `https://openrouter.ai/<vendor>/<model-slug>`. For example [`glm-5.2`](https://openrouter.ai/z-ai/glm-5.2), [`claude-opus-5`](https://openrouter.ai/anthropic/claude-opus-5), [`gpt-5.6-sol`](https://openrouter.ai/openai/gpt-5.6-sol).
- If you genuinely cannot determine your own model, **say so in the body** rather than inventing a slug or quietly dropping the attribution.
{{ if .harnessName }}
The harness half is already correct above — you are running under **{{ .harnessName }}**. Do not substitute a different one.
{{- else }}
Name the harness you are running under, linked to its home page.
{{- end }}

Whatever the harness is, **its link must be a publicly reachable URL — never a `{{ .giteaUrl }}` one.** Most of these footers land on GitHub, where a private Gitea link is a dead link for every reader. Harness → https://github.com/stump-wtf/harness (not its Gitea canonical), Crush → https://github.com/charmbracelet/crush, Claude Code → https://claude.com/claude-code. See "Never link Gitea in anything public" above.

Same formatting rule as the other identity: no horizontal rule before the footer — no `<hr/>`, no `---`/`***`/`___`. Blank line, then the footer line.

## What you may and may not do on your own

- Joe reviews and merges. Do not merge your own PRs into a `{{ $human }}`-, `stump.wtf`- or `stumpcloud`-owned repo unless he asked you to.
- You have push, not admin, on most of those repos. For settings-level operations (Pages, collaborators, branch protection), say what you need rather than trying and failing — Joe can do it in one command.
