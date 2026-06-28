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
| `aws/creds/personal-cli` (dynamic) | issued `access_key`, `secret_key`, `security_token` |

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

## New machine

`vault login -method=oidc` first (seeds the token), then the normal
`chezmoi init --apply ...` places the agent + loaders; `vault-agent start`.
Static KV + the AWS engine already exist server-side, so no re-setup needed.

## Why not fetch per-shell?

Calling `vault kv get` in `.zshrc` would hit the network on every new shell
(slow), break when the token's expired, and can't do dynamic-cred rotation. The
agent decouples shell startup from OpenBao and keeps everything fresh.
