---
sidebar_position: 5
title: Crush
---

# Crush

[Crush](https://github.com/charmbracelet/crush) is the second agent CLI on every
box — Charm's terminal coding agent. This repo runs **Joe's fork**, which adds
the *channels* feature the Signal-driven harness depends on.

## Where the binary comes from

The fork keeps the upstream module path and ships no release binaries, so there's
nothing to `go install` or download. `.chezmoiscripts/run_after_30-install-crush.sh`
builds it from the `~/.local/share/crush-src` external into `~/.local/bin/crush`,
which sorts ahead of `/opt/homebrew/bin` on `PATH` — so it transparently shadows
any Homebrew `crush` without a `brew uninstall`.

It runs on **every** apply but is cheap: it fingerprints the clone by git `HEAD`
and only rebuilds when `HEAD` moves. (`run_onchange_` would be wrong here — the
*fork* updating doesn't change the *script*, so an onchange gate would never
re-fire.) For an immediate pull + rebuild:

```bash
chezmoi apply --refresh-externals
```

## Providers

`~/.config/crush/crush.json` declares five providers. Every credential is emitted
as a **`"$VAR"` reference Crush expands at runtime** — never a literal value.

| Provider | Credential | Source |
| --- | --- | --- |
| `openai` | `$OPENAI_DIRECT_API_KEY` | Derived in `env.zsh` from the raw OpenAI key, *before* the LiteLLM gateway shadows `OPENAI_API_KEY` |
| `litellm` | `$LITELLM_API_KEY` | The StumpCloud gateway |
| `gemini` | `$GEMINI_API_KEY` | Google AI Studio, direct |
| `zai` | `$ZAI_API_TOKEN` | Z.ai GLM Coding Plan — `glm-5.2` / `glm-5.3` |
| `hyper` | `$HYPER_API_KEY` | charm.land |

All five render **unconditionally**, by design:

:::danger[Never gate a provider block on `if env`]
A gate is evaluated at **apply** time, but the secret is only needed at **run**
time — so the gate buys nothing (no key lands in the file either way) while
creating a silent, recurring outage.

Any `chezmoi apply` from a shell without the Vault-rendered environment — an
agent's non-interactive Bash, a launchd/systemd timer, a plain `chezmoi apply` in
a subshell — saw every gate as false and wrote `"providers": {}`. That is valid
JSON and exits 0, so nothing failed loudly; Crush simply refused to start, and
the usual next step was pasting a key into Crush's TUI, **persisting a plaintext
secret outside OpenBao**.

The accepted trade-off: on a machine that genuinely lacks a key, the provider is
listed and fails when selected. One dead entry beats zero providers and an
unusable Crush. A test (`test/czu-run-env.bats`) greps for this.
:::

**No default model is pinned.** Crush persists your pick in its own data config
(`~/.local/share/crush/crush.json`), which chezmoi doesn't manage. The
`crush-signal` harness is the exception — it points `CRUSH_GLOBAL_DATA` at
`~/.local/share/crush-signal/crush.json` to pin `glm-5.2` for that session only,
leaving your interactive `crush` alone.

## MCP servers

Crush gets its own MCP block — it does **not** read `mcp-servers.json`:

| Server | Transport | Notes |
| --- | --- | --- |
| `filesystem` | stdio | `@modelcontextprotocol/server-filesystem`, scoped to `~/src` |
| `gitea` | stdio | Remaps `GITEA_ACCESS_TOKEN` ← `$GITEA_TOKEN` |
| `outline` | http | The wiki |
| `signal` | stdio | `uv run … --channel` — the channels feature the fork adds |
| `chrome-devtools` | stdio | Drives a local Chrome |
| `aws-knowledge` | http | **Public AWS docs, no auth** — Crush only |
| `aws` | stdio | The real account, via the SigV4 proxy |
| `memory` / `sequential-thinking` | stdio | Reference MCP servers |
| `cairn` | http | Artifact sharing |
| `switchboard` | http | The durable todo queue |
| `msgbrowse` | http | Local endpoint served by the msgbrowse desktop app |

`aws-knowledge` and `aws` are **different servers**: the first is public
documentation and needs no credential; the second reaches the real account and
can change resources.

**There is no `github` MCP server.** The hosted one at `api.githubcopilot.com` was
retired; GitHub work goes through the [`gh` CLI](https://cli.github.com/), which is
authenticated from the environment (`GH_TOKEN`/`GITHUB_TOKEN`) and so works in
headless and daemon-launched sessions too. `gitea` above is a real MCP server and
is unaffected.

A long `allowed_tools` list in the same file pre-approves the read-only tools
across these servers, so routine work doesn't stop on a permission prompt.

No identity is rendered into the `signal` block. `signal-mcp` resolves
`SIGNAL_MCP_ACCOUNT` / `_OPERATOR` / `_PREFIX` from its **runtime** env, which
OpenBao provisions per-user — see [Agent rules & identity](agents).

:::note[Don't add self-referential env entries]
`"SIGNAL_MCP_X": "$SIGNAL_MCP_X"` looks harmless and isn't. Crush expands `$VAR`
from its own environment and appends the result to `os.Environ()` for the child,
so a self-mapping reproduces plain inheritance when the var is set — and pins an
**empty** value when it isn't. `signal-mcp` then sees the var set-but-empty
rather than unset. A thin-env launch is fixed at the source (the harness
`env_file`, or `czu` sourcing secrets), not here.
:::

## Rules and skills

- **Rules** — `~/.config/crush/CRUSH.md` is composed from the same partials as
  `~/.claude/CLAUDE.md`. See [Agent rules & identity](agents).
- **Repo-local skills** — four ship in-repo (`go-patterns`, `openspec`,
  `security-review`, `terraform-patterns`).
- **External skills** — chezmoi externals clone `claude-skills`,
  `claude-plugin-sdd` and `claude-plugin-harness` into
  `~/.config/crush/skills-ext/`. Crush discovers skills through this path,
  **not** through the Claude plugin marketplace mechanism — adding a plugin in
  `claude-plugins.tsv` does not give it to Crush.
- **LSP** — Go, Python, Ansible, YAML, Markdown, Terraform and JSON servers are
  wired up in `crush.json`.

## Semantic search

The fork ships `semantic_index` and `semantic_search` — a vector index over the
working repo, stored in the project's own SQLite database. They answer the
questions `grep` is bad at (*where is auth handled*, *what decides whether to
retry*); for an exact symbol or string literal `grep` is still the right tool.
This is the same idea as [qmd](../services#qmd-re-indexing), scoped to one repo and built on
demand rather than on a timer.

Both tools are **opt-in and register only when an `embeddings` block is
present** in `crush.json`, so the wiring is the whole feature:

```json
"embeddings": {
  "base_url": "https://litellm.stump.rocks/v1",
  "api_key": "$LITELLM_API_KEY",
  "model": "bge-m3",
  "dimension": 1024
}
```

Embeddings come from **`bge-m3` on the ie01 RTX A2000 Ada**, served by
Hugging Face text-embeddings-inference. Indexing therefore costs wall time and
nothing else — no per-token bill.

:::note[Why the gateway and not `bge-m3.stump.wtf` directly]
The TEI container has its own vhost, but it sits behind oauth2-proxy, which
answers a Bearer token with an SSO redirect. Crush speaks plain OpenAI auth, so
that path can't authenticate. LiteLLM already fronts the same container
in-cluster (`hosted_vllm/bge-m3` → `http://bge-m3:8000/v1`) behind its own API
key, and that key is already in the environment for the `litellm` provider.
:::

:::warning[`dimension` is dictated by the model, not chosen]
`BAAI/bge-m3` emits 1024 floats and TEI ignores OpenAI's `dimensions`
truncation parameter, so 1024 is the only value that works — Crush's default of
768 would mismatch every insert. The number is baked into the `vec0` table when
it's created; changing it later fails with an actionable error and needs a
reindex (drop `chunks` and `chunk_vectors`, re-run `semantic_index`).
:::

Indexing is **on demand**: nothing triggers it at apply time or session start.
Run `semantic_index` when you want the index; files whose contents and embedding
model haven't changed are skipped, so re-runs are cheap. `crush_info` reports
the model, dimension and chunk count under `[semantic_index]`.

## Config gets rewritten under you

Crush rewrites `~/.config/crush/crush.json` in place during config migrations and
TUI actions. That trips chezmoi's changed-since-last-write guard, which would
otherwise prompt on every interactive `czu` and *silently skip* the file on the
scheduled one. `czu` handles it: `czu_reassert_targets` force-applies just that
target before the main apply, so the render always wins. Runtime state belongs in
Crush's own data config, which is exactly where Crush keeps it.
