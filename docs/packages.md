# Package management (bundlers)

Tooling is declarative: add a line to a manifest, `chezmoi apply`, done. You never
have to remember an install command. Works on macOS and Ubuntu (ie01/ie02).

## Homebrew bundle — the main list

`~/.Brewfile` (managed; source `dot_Brewfile`) is the single source of truth,
installed with `brew bundle --global`. The chezmoi bootstrap runs it
automatically; you can run it anytime.

```sh
chezmoi edit ~/.Brewfile          # add:  brew "ripgrep"
chezmoi apply                     # installs it (runs brew bundle)
# or directly:
brew bundle --global
brew bundle check --global        # are all deps installed?
```

- **macOS only.** Homebrew is **not** installed on Linux — Ubuntu uses apt (below).
- `cask` lines are macOS-only, guarded with `if OS.mac?`.
- Optional tools are listed commented-out; uncomment to enable. Nothing installs
  until you uncomment it.

## Ubuntu / apt — the Linux list

On Linux the package script uses **apt only** (no Homebrew). The list lives in
`~/.config/dotfiles/apt-packages.txt` (managed; source `dot_config/dotfiles/apt-packages.txt`),
one package per line — the apt counterpart to the Brewfile.

```sh
chezmoi edit ~/.config/dotfiles/apt-packages.txt   # add: ripgrep
chezmoi apply                                      # sudo apt-get install …
```

`vault` and `gh` are installed from their official **apt repos** by the package
script (not listed in the manifest). Tools without a clean apt package (e.g. `yq`,
`tea`, `gitleaks`) can be added as binary installs in the script's Linux branch.

## Go tools

`~/.config/dotfiles/go-tools.txt` (managed) lists `go install` targets, one module
path per line. Installed by `run_onchange_after_10-install-packages.sh` when `go` is
present (`brew "go"` is in the Brewfile, so the toolchain is there on macOS).

```sh
chezmoi edit ~/.config/dotfiles/go-tools.txt   # add: github.com/x/y@latest
chezmoi apply
```

## crush — Joe's fork, built from source

[Crush](https://github.com/joestump-agent/crush) is Joe's agent-account fork of
Charm's Crush (a terminal AI coding agent). The fork adds a first-class **`litellm` provider type**
that auto-discovers every model from the LiteLLM gateway's `/v1/models` endpoint
and enriches them via `/model/info` — so `~/.config/crush/crush.json` (managed;
source `dot_config/crush/crush.json.tmpl`) needs no hand-maintained model list and
no plaintext key: it points at `https://litellm.stump.rocks/v1` with
`api_key: "$LITELLM_API_KEY"` (rendered from OpenBao by the Vault Agent) and
`discover_models: true`.

It can't be `go install`-ed (the fork keeps the upstream module path and ships no
release binaries), so chezmoi clones the source via a git-repo external to
`~/.local/share/crush-src` and `run_after_install-crush.sh` builds it to
`~/.local/bin/crush` — which shadows any Homebrew `crush` (that dir sorts ahead on
PATH). The build reruns only when the clone's HEAD moves.

```sh
chezmoi apply --refresh-externals   # pull the latest fork commit + rebuild
crush                               # ~/.local/bin/crush (the fork)
```

## vault — installed separately, OS-aware

`vault` (the OpenBao-compatible client) is **not** in the Brewfile. HashiCorp moved
it to their own tap, which Homebrew gates behind `brew trust`, and on Ubuntu the
canonical install is HashiCorp's apt repo. So a dedicated idempotent step in
`run_onchange_after_10-install-packages.sh` handles it:

- **macOS:** `brew tap/trust hashicorp/tap` + `brew install hashicorp/tap/vault`.
- **Ubuntu:** adds HashiCorp's apt repo + `apt-get install vault`.

## How bootstrap sequences it

| Phase | Script | Does |
| --- | --- | --- |
| before | `run_once_before_10-install-prereqs.sh` | **macOS:** install Homebrew · **Linux:** apt essentials (zsh/git/curl…) — no Homebrew · then Oh My Zsh |
| *(files)* | chezmoi apply | writes `~/.Brewfile`, `apt-packages.txt`, `go-tools.txt`, etc. |
| after | `run_onchange_after_10-install-packages.sh` | **macOS:** `brew bundle` · **Linux:** `apt-get install` (+ gh/vault apt repos) · then Go tools |
| after | `run_after_install-crush.sh` | build Joe's crush fork (`~/.local/share/crush-src` → `~/.local/bin/crush`) when its HEAD moves |
| after | `run_once_after_20-configure-git-hooks.sh` | wire the gitleaks hook |

## Adding another ecosystem (npm, pipx, cargo…)

Follow the Go pattern: add a manifest file (e.g. `dot_config/dotfiles/npm-tools.txt`)
and a loop in `run_onchange_after_10-install-packages.sh` guarded by `command -v npm`.
Keep the install idempotent and non-fatal.
