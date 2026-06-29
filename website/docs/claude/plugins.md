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
~/.config/claude-marketplaces/claude-personal  personal@claude-personal
```

GitHub marketplaces add by `owner/repo`. The **private Gitea** one
(`claude-personal`) can't be HTTP-fetched, so a chezmoi **external** clones it
locally (refreshed every **24h**) and it's added as a **local-path** marketplace.

## Propagation

Local-path marketplaces (`claude-personal`) **auto-reinstall** when the clone's git
HEAD moves — so newly-pushed skills appear without bumping the plugin `version`
(which `claude plugin update` otherwise requires, and which is easy to forget). The
last-installed HEAD is tracked per plugin in
`~/.config/dotfiles/.claude-plugin-state/`. For an immediate pull + propagate:

```bash
chezmoi apply --refresh-externals
```

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
