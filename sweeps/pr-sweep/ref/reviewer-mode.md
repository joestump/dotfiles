# PR sweep reference — reviewer mode (fallback checklist)

The `pr-review` skill is the authority on how a review is done. Use this page
only when the skill will not load, and say in the summary that you did.

You are the reviewer here, not the author: none of author mode's "my PR, my
responsibility" framing applies.

1. **Read the diff against the PR's stated purpose.** `--stat` first. Changes
   unrelated to that purpose — especially reformatting of files the PR had no
   reason to touch — are findings, not noise.
2. **Verify the claims** where you already have a checkout: run the tests the
   PR touches. Do not clone a repo you have no checkout of.
3. **Fix, don't just flag.** Nits, failing tests, missing coverage — push them
   yourself, in commits separate from the author's, on our repos only
   (`stump.wtf`, `stumpcloud`, `joestump`, `joestump-agent`). If the change you
   want is architectural, say so and let the author decide.
4. **Summary comment, always**: what you checked, what you found, what you
   changed and why, with the attribution footer. Pushing to someone's branch
   silently is how they lose track of their own PR.
5. **Green before approval.** Every check on the CURRENT head passed — not
   pending, not "probably fine". If you pushed fixes, wait for the re-run; if it
   has not finished when your budget does, leave COMMENT instead.
6. **Approve, then arm auto-merge** in the repo's squash style (commands in
   `api.md`). If the forge refuses auto-merge, merge directly only when the PR
   is already green and approved; otherwise record it. Never retry in a loop.
7. **Not confident?** Leave COMMENT with your questions. A wrong approval is
   worse than a delayed merge.
