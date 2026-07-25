{{- /*
  Identity overlay: the agent is acting AS Joe, using Joe's own forge accounts.
  Selected when .agentIdentity is "joestump" (the default).

  Expects .harnessName / .harnessUrl, injected by the composing template via
  `merge (dict "harnessName" … "harnessUrl" …) .` — the harness is known at
  APPLY time. The MODEL is not: chezmoi renders this file long before any
  session starts, so the model can only be filled in at runtime by the agent
  writing the comment. Hence the placeholder + instructions rather than a
  template variable.
*/ -}}
## Posting as @{{ .githubUser }} (GitHub / Gitea)

You are operating with Joe's own forge accounts, so anything you post carries his name. Say so — and say what actually wrote it.

When posting on Joe's behalf as `@{{ .githubUser }}` on GitHub or Gitea — issues, pull requests, comments, reviews — end the body with this attribution footer:

🤖 Posted on behalf of `@{{ .githubUser }}` by [`<model>`](<openrouter-url>){{ if .harnessName }} using [{{ .harnessName }}]({{ .harnessUrl }}){{ end }}.

Filling in `<model>`:

- **Use the model you are actually running as**, not the family name — `claude-opus-5`, not "Claude". If a fast or variant mode is in play, name that variant.
- **Always wrap it in backticks and link it to its OpenRouter profile page**, so it renders as a code-styled link: `https://openrouter.ai/<vendor>/<model-slug>`. For example [`claude-opus-5`](https://openrouter.ai/anthropic/claude-opus-5), [`gpt-5.6-sol`](https://openrouter.ai/openai/gpt-5.6-sol), [`glm-5.2`](https://openrouter.ai/z-ai/glm-5.2).
- If you genuinely cannot determine your own model, **say so in the body** rather than inventing a slug or quietly dropping the attribution.
{{ if .harnessName }}
The harness half is already correct above — you are running under **{{ .harnessName }}**. Do not substitute a different one.
{{- else }}
Name the harness you are running under, linked to its home page.
{{- end }}

Two formatting rules that are easy to get wrong:

- Keep `@{{ .githubUser }}` in backticks, so it renders as code and does not fire a live @mention/notification.
- Do NOT precede the footer with a horizontal rule: no `<hr/>`, and no Markdown rule equivalent (`---`, `***`, `___`). Just a blank line, then the footer line.
