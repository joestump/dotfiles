---
sidebar_position: 2
title: Spokes — Utility Nodes (Linux)
---

# Installing a Spoke

Spokes are the Linux boxes you boot up and tear down — `ie01`, `ie02`, random
workers. They're lean and **apt-only**: no Homebrew, no laptop-grade tooling,
and they're provisioned *from* [the hub](mothership.md) rather than set up by
hand.

## From the hub (recommended)

> ⚡ **One shot: `czinit <host>`** — the fastest path. In a single command it seeds
> the node's Gitea credentials, installs chezmoi and runs `init --apply`, then logs
> the box into OpenBao so secrets render (AppRole first, OIDC as fallback). You only
> click **Authorize** if the browser tab opens:
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

> ⚠️ **Private fork over SSH?** This repo is public, so the plain HTTPS clone just
> works. If you're running a **private fork**, the clone needs credentials on the
> node: either use the SSH clone URL (`git@…:you/dotfiles.git`) if that box's key is
> on your forge account, or stash a token in git's credential store there once.
> Also: `<host>` must actually resolve from the hub — use a Tailscale name or FQDN
> like `ie01.stump.rocks`, not a bare `ie01`.

## On the box directly

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

:::danger[No `--source`]
A bare `init` clones into chezmoi's default source dir — which **is** the
production clone under the two-checkout model. A fresh spoke gets no
`~/src/dotfiles` at all; that path is the development workbench, and it only
exists where someone develops. Passing `--source` leaves the rendered config and
the clone pointing at different places. See [Editing](../workflow).
:::

### What's different from the hub

- **No Homebrew.** `run_once_before_10-install-prereqs.sh` detects Linux and uses
  `apt` for the essentials (`zsh git curl …`).
- **Packages via apt.** `run_onchange_after_10-install-packages.sh` installs from
  `~/.config/dotfiles/apt-packages.txt`, plus `gh` and `vault` from their official
  apt repos. The `Brewfile` is ignored on Linux.
- **No desktop apps.** The macOS-only pieces (Claude Desktop, the msgbrowse cask)
  simply don't apply here — that's why the [hub must be macOS](mothership.md).
- **Services are `systemd --user`,** not launchd: `vault-agent.service`,
  `signal-daemon.service`, `harness.service`, plus the `czu`, qmd and
  stale-detector timers. See [Services](../services).
- Uses `sudo` for apt — passwordless or interactive sudo required.

## Then, secrets

`czinit` already does this. Doing it by hand, from your **laptop** — the node
needs a machine identity, not an interactive login:

```bash
czapprole joestump@ie02.stump.rocks   # mints a secret_id and ships it to the node
```

That gives the node's Vault Agent an AppRole it renews itself, so it never dies
at a token max-TTL. The OIDC path is the fallback, and it needs a tunnel back to
your laptop's browser:

```bash
vault-login joestump@ie02.stump.rocks   # opens the tunnel AND logs in there
```

The agent talks to OpenBao directly, so once the node has an identity everything
renders without a tunnel. See [Secrets](../secrets).

> 💡 **Re-installing a spoke** — if a node gets into a weird state, nuke chezmoi's
> cache and re-run; it re-clones HEAD cleanly:

> ```bash
> rm -rf ~/.local/share/chezmoi ~/.config/chezmoi ~/.cache/chezmoi
> sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://gitea.stump.rocks/joestump/dotfiles.git
> ```
