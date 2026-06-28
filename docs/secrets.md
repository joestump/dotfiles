# Secrets — OpenBao + Vault Agent

Secrets never live in files in this repo or in `~/.zprofile`. They live in
**OpenBao** (`https://vault.stump.rocks`, an OpenBao 2.5.0 server). A **Vault
Agent** running under launchd fetches them and renders them to local env files on
a schedule; an Oh My Zsh file sources those files into your shell.

> **Client note:** use the **`vault`** CLI (HashiCorp, API-compatible with
> OpenBao). The Homebrew `bao` binary is the unrelated BLAKE3 hashing tool — do
> not use it for secrets.

## How it fits together

```
OpenBao server  ──►  Vault Agent (launchd: rocks.stump.vault-agent)  ──►  ~/.config/vault/secrets-*.env (0600)
  KV: secret/personal/*        token_file auto-auth (~/.vault-token)         │
  AWS: aws/creds/personal-cli  renders + renews on a schedule               ▼
                                                          ~/.oh-my-zsh/custom/secrets.zsh  (source)
```

- **`~/.config/vault/agent.hcl`** — agent config (from `dot_config/vault/agent.hcl.tmpl`).
- **`secrets-static.env.ctmpl`** → `secrets-static.env` — static KV secrets.
- **`secrets-aws.env.ctmpl`** → `secrets-aws.env` — dynamic, short-lived AWS creds.
- **`custom/secrets.zsh`** — sources every `~/.config/vault/secrets-*.env` (guarded).
- **`custom/vault-agent.zsh`** — `vault-agent {start|stop|restart|status|log|env}`.

### KV layout (KV v2 @ mount `secret/`)

| Path | Fields |
| --- | --- |
| `secret/personal/llm` | `OPENAI_API_KEY`, `LITELLM_API_KEY`, `GEMINI_API_KEY` |
| `secret/personal/gitea` | `GITEA_TOKEN` |
| `secret/personal/pocketid` | `POCKETID_API_KEY` |
| `secret/personal/garage` | `GARAGE_ACCESS_KEY`, `GARAGE_SECRET_KEY` |
| `secret/personal/outline` | `OUTLINE_API_TOKEN` |
| `secret/personal/aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (static) |
| `secret/personal/ssh` | `id_rsa`, `id_rsa.pub` → rendered to `~/.ssh/` (files, 0600/0644) |

> **AWS** is currently **static** KV. To switch to dynamic short-lived creds, run
> `scripts/openbao-aws-setup.sh` and repoint `secrets-aws.env.ctmpl` at
> `aws/creds/personal-cli` (`.Data.access_key` / `.Data.secret_key`).
>
> **SSH keys** are rendered as files, not env vars — the agent keeps
> `~/.ssh/id_rsa{,.pub}` in sync from `secret/personal/ssh` (note the dotted field
> `id_rsa.pub` needs `index .Data.data "id_rsa.pub"` in the template).

> **Convention for a new secret:** one path per service, `secret/personal/<service>`,
> with fields named like the env var. Add it to KV (`vault kv put …`), add a
> matching `{{ with secret "secret/data/personal/<service>" }}` block to
> `dot_config/vault/secrets-static.env.ctmpl`, then `vault-agent restart`.

> Assumes KV v2 at `secret/`, OIDC auth enabled, and the AWS engine at `aws/`.
> Adjust paths in the `*.ctmpl` files + scripts together if your mounts differ.

## One-time bring-up (the cutover)

The client files are already applied (`chezmoi apply`). Do the rest in order:

```sh
# 1. Authenticate (seeds ~/.vault-token, which the agent reads + renews)
export VAULT_ADDR=https://vault.stump.rocks
vault login -method=oidc

# 2. Load your STATIC secrets into KV (run where the old ~/.zprofile is sourced)
~/.local/share/chezmoi/scripts/load-static-secrets.sh

# 3. SERVER-SIDE: configure dynamic AWS creds (admin; needs an AWS root cred)
#    Read the script header first — you must pick a credential_type + policy.
export AWS_VAULT_ROOT_ACCESS_KEY=... AWS_VAULT_ROOT_SECRET_KEY=...
~/.local/share/chezmoi/scripts/openbao-aws-setup.sh
vault read aws/creds/personal-cli         # sanity-check it issues creds

# 4. Start the agent (renders ~/.config/vault/secrets-*.env)
vault-agent start
vault-agent status
vault-agent env                           # should show your exports

# 5. Reload your shell — secrets now come from the agent
exec zsh
env | grep -E 'OPENAI_API_KEY|AWS_ACCESS_KEY_ID' >/dev/null && echo "loaded ✅"

# 6. CUTOVER: remove the plaintext secret lines from ~/.zprofile (keep the
#    non-secret lines: VAULT_ADDR, GITEA_URL, NODE_EXTRA_CA_CERTS, brew shellenv).
#    A timestamped backup already exists at ~/.zprofile.bak.*

# 7. ROTATE every previously-exposed credential at its provider, then re-run
#    step 2 (and step 3 for AWS) so OpenBao holds the new values.
```

Until step 4 succeeds, `custom/secrets.zsh` is a silent no-op and your existing
`~/.zprofile` keeps working — nothing breaks during bring-up.

## Day-to-day

- **Rotate a static secret:** `vault kv put secret/personal/llm OPENAI_API_KEY=sk-new...`
  — the agent re-renders within `static_secret_render_interval` (5m); `exec zsh`.
- **AWS creds expired/odd:** `vault-agent restart` forces a fresh lease.
- **Token expired (hit max TTL):** `vault login -method=oidc` again; the agent
  picks up the new `~/.vault-token`.
- **See what's happening:** `vault-agent log` (tails `~/.config/vault/agent.log`).

## New machine — what chezmoi does vs. what you do

`chezmoi init --apply https://gitea.stump.rocks/joestump/dotfiles.git` **configures
everything client-side automatically**: installs the `vault` CLI + tools + Oh My
Zsh, writes the agent config (`~/.config/vault/agent.hcl` + the `*.ctmpl`), installs
the launchd job, and drops `custom/secrets.zsh` / `custom/vault-agent.zsh`.

Two things are **not** baked into the image (they can't be — they're identity /
already-global):

1. **`vault login -method=oidc`** — interactive, mints your `~/.vault-token`.
2. **`vault-agent start`** — loads the launchd job (needs the token first).

The KV data and the AWS secrets engine are **server-side and already set up once
globally** — a new machine never re-runs `load-static-secrets.sh` or
`openbao-aws-setup.sh`. So a new laptop is just:

```sh
chezmoi init --apply https://gitea.stump.rocks/joestump/dotfiles.git
vault login -method=oidc
vault-agent start
exec zsh
```

## Remote machines & SSH

The agent itself talks to `https://vault.stump.rocks` directly, so on a remote
host it works as long as the host can reach that URL — no tunnel needed for normal
operation. The **only** step that needs a tunnel is the interactive **OIDC login**,
because its `localhost:8250` callback has to reach your laptop's browser.

The tooling detects this for you. If you run `load-static-secrets.sh`,
`openbao-aws-setup.sh`, or `vault-oidc-login` while SSH'd into a box without a
valid token, it prints the exact tunnel commands. Two ways to log in remotely:

```sh
# A) From your LAPTOP — one step (tunnels in AND logs in on the remote):
vault-login <remote-host>

# B) From the REMOTE — it tells you to open, on your laptop:
ssh -L 8250:localhost:8250 <user>@<remote-host>
#    then back on the remote:
vault-oidc-login        # or: vault login -method=oidc
```

If the remote can't even reach `vault.stump.rocks`, also forward it:
`ssh -L 8200:vault.stump.rocks:443 <user>@<remote>` and
`export VAULT_ADDR=https://localhost:8200`.

## Why not fetch per-shell?

Calling `vault kv get` in `.zshrc` would hit the network on every new shell
(slow), break when the token's expired, and can't do dynamic-cred rotation. The
agent decouples shell startup from OpenBao and keeps everything fresh.
