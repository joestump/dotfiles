---
title: git-auto-fetch
---

# git-auto-fetch

Runs `git fetch --all` in the background every time the prompt appears inside a
repo, throttled to once per `GIT_AUTO_FETCH_INTERVAL` (default 60s). Fetches
are silent, non-interactive (SSH in BatchMode, no terminal prompts), and logged
to `.git/FETCH_LOG`.

## Pro tips

- **This is what keeps the spaceship prompt honest** — the ⇣/⇡ behind/ahead
  arrows only know about commits your local repo has fetched. With auto-fetch,
  an agent pushing to gitea.stump.rocks from another session shows up in your
  prompt within a minute, no manual `git fetch` needed.
- **Per-repo kill switch**: run `git-auto-fetch` (the function, no args) inside
  a repo to toggle it — it drops a `NO_AUTO_FETCH` guard file in `.git/`.
  Worth doing in huge or slow-remote repos.
- **The `--force-with-lease` caveat**: because fetches happen behind your back,
  your lease is always "fresh" — `gpf` can overwrite remote commits you never
  actually looked at. Solo on Gitea this rarely bites, but on shared GitHub
  branches, check `glol` before force-pushing.
- **Debugging a repo that feels stale?** `cat .git/FETCH_LOG` — its mtime is
  the throttle timestamp, and fetch errors (dead remotes, auth failures) land
  there instead of your terminal.
- It fetches **all remotes**, so repos with both a Gitea `origin` and a GitHub
  `upstream` (like the navidrome-ldap fork) stay current on both sides for
  free.
