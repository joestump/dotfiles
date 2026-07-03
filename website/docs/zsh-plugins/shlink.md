---
title: shlink
---

# shlink

Home-grown plugin ([joestump/shlink-zsh](https://gitea.stump.rocks/joestump/shlink-zsh))
that wraps the [Shlink](https://shlink.io/) REST API at https://u.stu.mp.
Requires `curl` + `jq` and a personal `SHLINK_API_KEY` in the environment.

| Command | Does |
|---|---|
| `shorten <url>` / `shlink shorten` | create a short link (prints + copies it) |
| `shlink ls [search]` | list links: slug · visits · target |
| `shlink visits <slug>` | total visit count |
| `shlink rm <slug>` | delete a link |
| `shlink tags` | list all tags |
| `shlink qr <slug>` | QR-code image URL for a slug |

## Pro tips

- **`shorten` copies to the clipboard automatically** (pbcopy/wl-copy/xclip) —
  shorten and paste straight into Signal or a doc, no mouse.
- **Custom slugs and tags**: `shorten https://... -s omg-outline -t omg,docs`.
  Memorable slugs beat random codes for links you'll say out loud; tags make
  `shlink ls` and `shlink tags` useful later.
- **`findIfExists` is on** — shortening the same URL twice returns the same
  short link instead of minting a duplicate. Safe to re-run.
- **`shlink ls outline`** searches targets and slugs server-side — quickest way
  to answer "did I already shorten this?"
- **`shlink qr <slug>`** returns the QR image URL (also copied) — handy for
  getting a link onto a phone without typing.
- Auth is per-key, not per-user: mint keys with
  `docker exec shlink-server shlink api-key:generate --name <who>`. Separate
  keys mean separate stats and independent revocation, so give agents and
  humans their own.
