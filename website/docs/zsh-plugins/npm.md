---
title: npm
---

# npm

Tab completion for npm plus camelCase aliases for the common subcommands. In
this repo its beat is the Docusaurus site in `website/` — the
`npm ci` / `npm start` / `npm run build` loop.

| Alias | Runs |
|---|---|
| `npmst` / `npmt` | `npm start` / `npm test` |
| `npmR` | `npm run` |
| `npmrb` / `npmrd` | `npm run build` / `npm run dev` |
| `npmS` / `npmD` | `npm i -S` / `npm i -D` (save to deps / devDeps) |
| `npmg` | `npm i -g` |
| `npmO` / `npmU` | `npm outdated` / `npm update` |
| `npmL0` | `npm ls --depth=0` |

## Pro tips

- **The docs-site loop compresses to three keystrokes-ish**: `npmst` in
  `website/` for the live-reload dev server, `npmrb` before pushing to catch
  broken links — Docusaurus only validates them on full builds, not in the
  dev server.
- **`npmR` + completion** is the discovery tool: type `npmR ` and hit tab to
  see every script in `package.json` — no more opening it to remember
  whether it's `serve` or `start`.
- **New Docusaurus deps are devDeps**: `npmD @docusaurus/theme-mermaid`, not
  bare `npm i`, so `package.json` stays honest for the next `npm ci`.
- **`npmO` before touching versions** — Docusaurus pins its own ecosystem
  tightly, and `npmU` respects semver ranges while a blind
  `npm i pkg@latest` doesn't.
- **F2 F2 toggles install↔uninstall** on the current or previous command —
  the "wrong package, undo it" key.
