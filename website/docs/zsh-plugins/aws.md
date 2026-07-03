---
title: aws
---

# aws

Profile/region helpers and CLI completion for the AWS CLI. Ships shell
functions (not aliases) for switching and inspecting AWS state, plus an
optional `<aws:profile>` segment in the right prompt.

| Function | Does |
|---|---|
| `asp <profile>` | export `AWS_PROFILE` (+ `AWS_DEFAULT_PROFILE`, `AWS_EB_PROFILE`); bare `asp` clears |
| `agp` / `agr` | print current profile / region |
| `asr <region>` | set `AWS_REGION` + `AWS_DEFAULT_REGION` |
| `acp <profile>` | like `asp` but resolves *actual* keys via STS (MFA/assume-role) |
| `aws_profiles` | list profiles from `~/.aws/config` |

## Pro tips

- **The big footgun here**: Vault Agent renders static `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` into every shell, and env-var credentials **beat**
  `AWS_PROFILE`. `asp someprofile` changes the prompt but not the keys being
  sent. To genuinely use a profile, `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY`
  first — or use `acp`, which exports that profile's real keys over the top.
- **Garage doesn't care about profiles at all** — talking to the ~4TB Garage
  bucket is just the env-var keys plus `aws s3 ... --endpoint-url https://<garage>`.
  The plugin's job there is completion, nothing more.
- `asp` with no args clears the profile vars — the quick "am I confused about
  which account this is hitting?" reset. `agp`/`agr` confirm in one word each.
- Tab-completion works on `asp`/`acp`/`asr`: profile and region names complete
  from `aws_profiles` / `aws_regions`.
- `SHOW_AWS_PROMPT=false` in `~/.zshrc` disables the RPROMPT segment if it
  crowds the Terraform/kubectx info.
