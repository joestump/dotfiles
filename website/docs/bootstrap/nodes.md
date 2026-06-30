---
sidebar_position: 2
title: Utility Nodes (Linux)
---

# Bootstrapping a Utility Node

Utility nodes are the Linux boxes I boot up and tear down — `ie01`, `ie02`, random
workers. They're lean and **apt-only**: no Homebrew, no laptop-grade tooling.

## From the mothership (recommended)

> ⚡ **One shot: `czinit <host>`** — the fastest path. In a single command it seeds
> the node's Gitea credentials, installs chezmoi and runs `init --apply`, then logs
> the box into OpenBao over OIDC so secrets render. You only click **Authorize** when
> the browser tab opens:
>
> ```bash
> czinit joestump@ie02.stump.rocks
> ```
>
> Everything below — the SSH clone, the credential note, and the [secrets](#then-secrets)
> step — is what `czinit` automates, shown here for when you need to run a piece by hand.

`chezmoi ssh` does the whole thing over SSH and drops you into a shell on the box:

```bash
chezmoi ssh <host> https://gitea.stump.rocks/joestump/dotfiles.git
```

> ⚠️ **Private repo over SSH** — the clone needs credentials on the node. If `chezmoi
> ssh` fails with `could not read Username for https://gitea.stump.rocks`, either use
> the **SSH clone URL** (`git@gitea.stump.rocks:joestump/dotfiles.git`) if that box's
> key is on your Gitea account, or stash a Gitea token in git's credential store there
> once. Also: `<host>` must actually resolve from your laptop — use a Tailscale name or
> FQDN like `ie01.stump.rocks`, not a bare `ie01`.

## On the box directly

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- \
  init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

### What's different from the mothership

- **No Homebrew.** `run_once_before_10-install-prereqs.sh` detects Linux and uses
  `apt` for the essentials (`zsh git curl …`).
- **Packages via apt.** `run_onchange_after_10-install-packages.sh` installs from
  `~/.config/dotfiles/apt-packages.txt`, plus `gh` and `vault` from their official
  apt repos. The `Brewfile` is ignored on Linux.
- Uses `sudo` for apt — passwordless or interactive sudo required.

## Then, secrets

Same as the mothership — the Vault Agent talks to OpenBao directly, so it works on a
node as long as it can reach `vault.stump.rocks`:

```bash
vault login -method=oidc      # over SSH? see the tunnel note in Secrets
vault-agent start
```

> 💡 **Re-bootstrapping a node** — if a node gets into a weird state, nuke chezmoi's
> cache and re-run; it re-clones HEAD cleanly:
>
> ```bash
> rm -rf ~/.local/share/chezmoi ~/.config/chezmoi ~/.cache/chezmoi
> sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
> ```
