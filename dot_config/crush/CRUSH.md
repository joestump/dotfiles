# Crush agent rules

## Git workflow

- **One branch per work item.** Never reuse a merged branch. If a PR was squash-merged, create a new branch for follow-up work.
- **Use git worktrees** when switching between parallel work items instead of stashing or branching in-place.
- **Always open a PR.** Pushed code without a PR is unfinished work. If you finish implementation, push AND open the PR in the same turn.
- **Never force-push to a branch that has an open PR** unless you are rebasing onto the latest main.
- **Rebase, don't merge main into your feature branch.** Keep history linear.

## Code quality

- **Every PR must include tests** for new or changed behavior. A PR with zero test files is incomplete.
- **Run `gofumpt -w .` before committing.**
- **Run `go test ./...` and `go vet ./...` before pushing.** Do not push broken builds.
- **CI must be green before a PR can merge.** Do not request review or merge until all checks pass.
- **If CI fails, fix it immediately** in the same branch — do not open a new PR for the same work item.

## Communication

- **Signal messages are only for channel-originated conversations.** Do not proactively send Signal messages for local work updates unless asked.
- **Keep PR descriptions accurate.** If the scope changed during review, update the body.
