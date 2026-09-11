# PR sweep reference — author mode

Your own PRs are yours to keep mergeable. Work in the PR branch's local checkout
under `~/src` (fetch, check out the branch, confirm it is the PR head), in a
worktree if the checkout is dirty. Three jobs, in this order.

## 1. Resolve merge conflicts — without rewriting history

You may NOT rebase a pushed PR branch and you may not force-push it. Instead:

1. `git fetch origin && git switch -c <branch>-v2 origin/<base>`
2. Replay the PR's commits onto it — `git cherry-pick origin/<base>..<old-branch>` —
   resolving conflicts on their merits.
3. Run the repo's checks (`make test lint` where they exist).
4. Push the new branch, open a replacement PR with the original description
   plus "Replaces #N", and close the old PR with a comment linking it.

Never merge the base branch into the PR branch. If a conflict needs a judgment
call you cannot make — two competing designs, a delete-versus-modify where
either answer loses work — leave the branch alone, say so on the PR, and flag it
in the summary.

## 2. Get CI back to green

Red checks on your own PR are yours to fix, not to report. Tail the failing
job's log (`gh run view <id> --log-failed | tail -n 80`), reproduce it locally
where you have a checkout, and fix the cause. Run the repo's checks before
pushing — for joestump/dotfiles that is `make test lint`; pre-existing
macOS-only bats failures are not regressions you caused.

If the failure is infrastructure — a runner offline, a missing image, an expired
registry token, a rate limit — do not paper over it: name the root cause in the
summary.

## 3. Answer the feedback

NEW feedback only: anything posted after your last commit or reply. Skip
threads you have already answered.

Make the requested change, minimal and in the surrounding style; commit with a
semantic prefix; push. Reply to each addressed thread with what changed and the
commit sha. Answer questions that need no code. Decline with a one-line reason
rather than ignoring a comment.

Every reply ends with the attribution footer from your rules.

## Guardrails

- Pushed to it this run? Its CI has not re-run, so do not merge it now.
- Fork-PR CI on Gitea can sit `pending` until Joe approves the Actions run; that
  PR is not eligible — note it.
- A merge refused with 403, or blocked by your permission layer: record it,
  never retry it, never route around it with a git CLI merge and push.
