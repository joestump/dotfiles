---
sidebar_position: 3
title: Plugins
---

# Plugins

`~/.config/dotfiles/claude-plugins.tsv` lists every plugin; a `run_after_` script
(runs on **every** apply) keeps each installed **and current** across Code on macOS
and Linux:

```
tobi/qmd                                       qmd@qmd
joestump/claude-plugin-sdd                     sdd@claude-plugin-sdd
joestump/claude-skills                         claude-skills@joestump
stump-wtf/claude-plugin-switchboard            switchboard@claude-plugin-switchboard
stump-wtf/claude-plugin-cairn                  cairn@claude-plugin-cairn
~/.config/claude-marketplaces/claude-personal  personal@claude-personal
https://gitea.stump.rocks/stump.wtf/claude-plugin-harness.git  harness@claude-plugin-harness
```

A marketplace source can be three things, and all three are in use:

| Form | Example | Why |
| --- | --- | --- |
| `owner/repo` | `tobi/qmd` | A public GitHub marketplace — added directly |
| A full git URL | the `claude-plugin-harness` line | Public, but only on Gitea: the GitHub mirror of that repo was never synced, so `owner/repo` would resolve to an empty repo |
| A local path | `claude-personal` | **Private** Gitea, so it can't be HTTP-fetched. A chezmoi **external** clones it (refreshed every 24 h) and it's added as a local-path marketplace |

:::note[These are Claude plugins, not Crush skills]
Crush discovers skills through `~/.config/crush/skills-ext/` — separate externals,
a separate mechanism. Adding a line here does **not** give it to Crush. See
[Crush](./crush#rules-and-skills).
:::

That external is **credential-guarded**: it's only declared on a node that has
Gitea credentials (a rendered OpenBao secrets file, or a stored git credential).
A git-repo external that can't authenticate aborts the whole `chezmoi apply`, so a
credential-less node skips the private marketplace instead of bricking its apply —
it reappears automatically once the node is provisioned.

## Propagation

The install script runs on **every** apply — not `run_onchange_`. New skills
pushed to the private marketplace don't change the `.tsv`, so an onchange gate
would never re-fire and those skills would never propagate. It's cheap when
nothing has moved: one `claude plugin list`.

The two marketplace kinds propagate differently:

- **Local-path** (`claude-personal`) — fingerprinted by the clone's git `HEAD`.
  When `HEAD` moves the plugin is **reinstalled**, because authors don't reliably
  bump the plugin `version` and `claude plugin update` is a no-op when the
  version is unchanged. That is exactly why a freshly-added skill used to
  silently fail to appear. The last-installed `HEAD` is tracked per plugin in
  `~/.config/dotfiles/.claude-plugin-state/`.
- **Remote** (GitHub, or a Gitea URL) — install-once. Their cache is refreshed
  with `marketplace update` **before every install attempt**, so a marketplace
  whose entry was broken when it was first cloned recovers on a later run.

For an immediate pull + propagate after pushing skills:

```bash
czu --refresh-externals
```

:::note[A parsing trap worth remembering]
`claude plugin list` is a *human-formatted* listing, not a machine interface — it
prints decorated lines like `❯ **claude-skills@joestump**`. An earlier version of
this script matched whole lines against it, which never matched anything, so
every plugin silently took the "not installed" branch forever and the
HEAD-moved refresh became dead code. The script now extracts the
`name@marketplace` token instead of trusting the layout.
:::

## Updating

Remote (GitHub) marketplaces are install-once. There is **no bulk update** — `claude
plugin update` requires a plugin argument in `<plugin>@<marketplace>` form, e.g.:

```bash
claude plugin update qmd@qmd
claude plugin update sdd@claude-plugin-sdd
claude plugin update claude-skills@joestump
```

In practice you rarely run these by hand: the `run_after_` script already updates
remote plugins and reinstalls the local-path one on every `chezmoi apply`.
