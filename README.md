# dotfiles

Personal dotfiles, managed with [chezmoi](https://www.chezmoi.io/) and backed by
self-hosted Gitea at <https://gitea.stump.rocks/joestump/dotfiles> (private).

Integrated with an existing [Oh My Zsh](https://ohmyz.sh/) install. chezmoi
manages **only** `~/.zshrc` and the contents of `~/.oh-my-zsh/custom/`. OMZ
self-updates the rest of its tree and is never touched by chezmoi.

## Separation of concerns

| Kind | Where it lives | Example |
| --- | --- | --- |
| Shell helper functions | one `*.zsh` file per helper in `~/.oh-my-zsh/custom/` (OMZ auto-sources these) | `custom/vault-login.zsh` |
| Non-secret config | direnv `.envrc` files in each project (hostnames, ports, AWS profiles, regions) | [`examples/envrc.example`](examples/envrc.example) |
| Secrets | **never** in env files or this repo — fetched at runtime from OpenBao (<https://vault.stump.rocks>) via `bao kv get` | inside `vault-login`, commented in the `.envrc` example |

No dotenvx. No committed `.env`. No second secrets path. A `gitleaks`
pre-commit hook blocks accidental secret commits.

## Add a helper (the convention)

1. Drop a `*.zsh` file in `~/.oh-my-zsh/custom/` — OMZ auto-loads it on next shell.
   ```sh
   $EDITOR ~/.oh-my-zsh/custom/my-helper.zsh
   ```
2. Bring it under chezmoi management, then commit and push:
   ```sh
   chezmoi add ~/.oh-my-zsh/custom/my-helper.zsh
   chezmoi cd
   git add -A && git commit -m "Add my-helper" && git push
   exit
   ```

## Apply on another machine

```sh
# Prereqs: brew install chezmoi direnv gitleaks ; Oh My Zsh already installed.
chezmoi init --apply https://gitea.stump.rocks/joestump/dotfiles.git
```

Thereafter, pull and apply updates with:

```sh
chezmoi update     # git pull + chezmoi apply
```

## What chezmoi manages here

```
~/.zshrc                          (seeded verbatim from the OMZ-generated file)
~/.oh-my-zsh/custom/vault-login.zsh
~/.oh-my-zsh/custom/direnv.zsh     (eval "$(direnv hook zsh)")
```

`.chezmoiignore` guarantees nothing else under `~/.oh-my-zsh/` is managed.

See [Architecture.md](Architecture.md) for the full design rationale.
