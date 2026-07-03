---
title: terraform
---

# terraform

Two-letter-ish aliases for the whole Terraform lifecycle, completion, and a
`tf_prompt_info` function that shows the active workspace in the prompt.

| Alias | Runs |
|---|---|
| `tf` | `terraform` |
| `tfi` / `tfiu` | `init` / `init -upgrade` |
| `tfp` / `tfpo` | `plan` / `plan -out tfplan` |
| `tfa` / `tfapp` | `apply` / `apply tfplan` |
| `tfa!` / `tfd!` | apply / destroy with `-auto-approve` |
| `tff` / `tffr` | `fmt` / `fmt -recursive` |
| `tfwl` / `tfws` | workspace list / select |

## Pro tips

- **The plan-file loop is the safe default**: `tfpo` writes `tfplan`, review
  it, `tfapp` applies exactly that plan — no drift between what you read and
  what runs. Save `tfa!` for throwaway sandboxes.
- **Workspace awareness is free**: `tf_prompt_info` reads
  `.terraform/environment` and shows `[workspace]` in the prompt (hidden for
  `default` in `$HOME`). For occasional infra work, that's the guard against
  applying to the wrong workspace after weeks away — glance before `tfa`.
- `tfwl` then `tfws <name>` is the two-command re-orientation when returning
  to a repo cold.
- Provider/backend errors after a `git pull`? `tfiu` (`init -upgrade`) fixes
  most of them; `tfir` (`init -reconfigure`) handles backend config changes.
- `tffr` before committing keeps `.tf` diffs about substance, not whitespace —
  it recurses into modules, unlike plain `tff`.
