---
title: zsh-autosuggestions
---

# zsh-autosuggestions

Fish-style ghost text: as you type, the most recent matching history entry
appears after the cursor in muted gray. It's a suggestion, not a completion —
one key accepts it. Cloned as a chezmoi external into
`~/.oh-my-zsh/custom/plugins/`.

| Key | Does |
|---|---|
| **Tab** | accept the suggestion (custom binding) |
| **→** / **End** | accept (stock bindings) |
| **Ctrl+→** | partial-accept, one word at a time |
| **Enter** | ignores the ghost text, runs only what you typed |

## Pro tips

- **Tab accepts here** — that's a custom widget in
  `~/.oh-my-zsh/custom/autosuggest-tab.zsh`, not stock behavior. When gray
  text is showing, Tab takes it; when there's none, Tab falls through to
  fzf-aware completion (so `**<Tab>` still works), then plain completion.
- **Partial accept is the underrated move**: Ctrl+→ invokes `forward-word`,
  which takes the suggestion one word at a time. Grab
  `ssh joestump@` from history, then type a different host.
- Suggestions come from the `history` strategy — verbatim replays of past
  commands, which is why the long `curl`/`launchctl`/`chezmoi` incantations
  resurface after two keystrokes. Add `completion` to
  `ZSH_AUTOSUGGEST_STRATEGY=(history completion)` if you want it to fall
  back to tab-completion guesses for never-typed commands.
- If the gray is hard to read on Catppuccin Mocha, tune it:
  `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"` (Mocha's overlay0).
- Typed something the suggestion contradicts? Just keep typing — the ghost
  text updates or vanishes. It never inserts anything without an accept.
