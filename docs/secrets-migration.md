# Secrets — OpenBao migration & how it works

Secrets never live in files or this repo. They live in OpenBao
(<https://vault.stump.rocks>) and chezmoi renders `~/.zprofile` from them at
`chezmoi apply` time. The repo only ever contains **OpenBao paths**, never values.

## How it works

- `~/.config/chezmoi/chezmoi.toml` sets `[vault] command = "bao"` (generated from
  `.chezmoi.toml.tmpl`). chezmoi's `vault` template function then runs
  `bao kv get -format=json <path>`.
- `private_dot_zprofile.tmpl` references `secret/personal/*` paths. On apply,
  chezmoi fetches each and writes `~/.zprofile` at mode `0600`.
- KV layout (KV v2 at mount `secret/`):

  | OpenBao path | Fields |
  | --- | --- |
  | `secret/personal/aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
  | `secret/personal/llm` | `OPENAI_API_KEY`, `LITELLM_API_KEY`, `GEMINI_API_KEY` |
  | `secret/personal/gitea` | `GITEA_TOKEN` |
  | `secret/personal/pocketid` | `POCKETID_API_KEY` |
  | `secret/personal/garage` | `GARAGE_ACCESS_KEY`, `GARAGE_SECRET_KEY` |

> If your OpenBao KV mount isn't `secret/` or isn't v2, adjust the paths in
> `private_dot_zprofile.tmpl` and `scripts/migrate-zprofile-to-bao.sh` together.

## One-time migration (do this once)

> ⚠️ Until the secrets exist in OpenBao, `chezmoi apply` will **fail on
> `~/.zprofile`** (the vault lookups error). Your existing `~/.zprofile` is
> untouched until you run apply, and a timestamped backup was made. Do the steps
> below to complete the cutover.

```sh
# 1. Authenticate to OpenBao
export VAULT_ADDR=https://vault.stump.rocks
bao login -method=oidc

# 2. Load the secrets currently in your environment into OpenBao
#    (run from a shell where the OLD ~/.zprofile is sourced)
~/.local/share/chezmoi/scripts/migrate-zprofile-to-bao.sh

# 3. Render ~/.zprofile from OpenBao and reload
chezmoi diff          # sanity-check
chezmoi apply
exec zsh

# 4. Rotate the previously-exposed credentials at their providers, then re-run
#    the migration script + `chezmoi apply` to store the new values.
```

## Changing a secret later

Update it in OpenBao, then re-render:

```sh
bao kv put secret/personal/llm OPENAI_API_KEY="sk-new..."   # patches that field set
chezmoi apply
exec zsh
```

## On a new machine

`bao login` first (apply needs to reach OpenBao), then the normal
`chezmoi init --apply ...` materializes `~/.zprofile` from OpenBao.
