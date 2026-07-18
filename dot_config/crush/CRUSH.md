# Crush agent rules

## Git hosting workflow

### Allowed repositories

You may open pull requests, issues, and fork repos **without asking** in the
following organizations/owners:

| Host    | Owner            | Permission              |
|---------|------------------|-------------------------|
| Gitea   | `stump.wtf`      | Full (PRs, issues, forks) — **origin of truth for shared repos** |
| GitHub  | `stump-wtf`      | Full — downstream mirror of `stump.wtf` |
| GitHub  | `joestump-agent` | Full (PRs, issues, forks) |
| GitHub  | `joestump`       | Full (PRs, issues, forks) |
| Gitea   | `joestump-agent` | Full (PRs, issues, forks) |
| Gitea   | `joestump`       | Full (PRs, issues, forks) |
| Gitea   | `stumpcloud`     | Full (PRs, issues, forks) |

**You MUST NOT open PRs, issues, or any other contributions against ANY other
organization or user on GitHub or Gitea without EXPLICIT, prior, per-action
approval from Joe.** When in doubt, ASK FIRST — never assume permission.

### Organizations — `joestump` + `joestump-agent` collaborate in `stump.wtf`

`joestump` (Joe) and `joestump-agent` (you) work together. **Shared repos of
origin/truth live on Gitea in the `stump.wtf` org (https://gitea.stump.rocks/stump.wtf)**
— that's where you branch, push, and open PRs (free self-hosted CI). Each repo
**auto-syncs to GitHub at https://github.com/stump-wtf** via a Gitea push mirror,
so GitHub is a read-only downstream — never push work directly to the GitHub
mirror. New shared work converges on `stump.wtf`; some older repos still live
under `joestump`.

### General rules

1. **Branch from latest main.** Run `git checkout main && git pull` before branching. Never reuse a merged branch.
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
