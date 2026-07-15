# Crush agent rules

## Git hosting workflow

### Allowed repositories

You may open pull requests, issues, and fork repos **without asking** in the
following organizations/owners:

| Host    | Owner            | Permission              |
|---------|------------------|-------------------------|
| GitHub  | `joestump-agent` | Full (PRs, issues, forks) |
| GitHub  | `joestump`       | Full (PRs, issues, forks) |
| Gitea   | `joestump-agent` | Full (PRs, issues, forks) |
| Gitea   | `joestump`       | Full (PRs, issues, forks) |
| Gitea   | `stumpcloud`     | Full (PRs, issues, forks) |

**You MUST NOT open PRs, issues, or any other contributions against ANY other
organization or user on GitHub or Gitea without EXPLICIT, prior, per-action
approval from Joe.** When in doubt, ASK FIRST — never assume permission.

### General rules

1. **Branch from latest main.** Run `git checkout main && git pull` before
2. **Branch naming.** Use `feat/<short-description>`, `bug/<short-description>`, or `toil/<short-description>`.
3. **Use git worktrees** when switching between parallel work items instead of stashing or branching in-place.
4. **Rebase, don't merge main into your branch.** Keep history linear.
5. **Commit with semantic prefixes** (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `sec:`).
6. **Always open a PR.** Pushed code without a PR is unfinished work. Push AND open the PR in the same turn.
7. **Label the PR.** Apply `feature`, `bug`, or `toil` label matching the branch type when creating the PR.
8. **Never force-push to a branch with an open PR** unless rebasing onto latest main.
9. **Watch CI after pushing.** Run `gh pr checks` to verify CI status. Do not walk away after push — confirm CI is green.
10. **CI must be green before merge.** If CI fails, fix immediately in the same branch.

## Code quality

- **Every PR must include tests** for new or changed behavior. A PR with zero test files is incomplete.
- **Run `gofumpt -w .` before committing.**
- **Run `go test ./...` and `go vet ./...` before pushing.** Do not push broken builds.

## Communication

- **Signal messages are only for channel-originated conversations.** Do not proactively send Signal messages for local work updates unless asked.
- **Keep PR descriptions accurate.** If the scope changed during review, update the body.
