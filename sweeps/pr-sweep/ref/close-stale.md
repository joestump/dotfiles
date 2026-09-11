# PR sweep reference — closing stale and superseded PRs

Only PRs authored by either identity. Comment first, always, with the
attribution footer. Close when any one of these holds:

1. **Superseded** — another PR merged the same change.
   "Closing — superseded by #NNN."
2. **No longer valid** — the underlying issue was closed or the work abandoned.
   "Closing — the underlying issue (#NNN) is no longer being pursued."
3. **Stale draft** — a draft with no new commits for 30+ days.
   "Closing stale draft — no updates in 30+ days. Reopen when ready."
4. **Abandoned** — a non-draft with no author activity for 60+ days and no
   reviewer engagement. "Closing due to inactivity — no updates in 60 days."

Age is a real signal for a PR, because an unmerged branch rots against a moving
`main`, in a way it is not for an issue. Even so, never close:

- a PR you pushed to or commented on earlier in this run;
- one that is approved and only waiting on CI or a merge — that PR is blocked,
  and belongs in the summary;
- one carrying prepared-but-unsubmitted upstream Crush work;
- a PR authored by anyone other than the two identities.

If a PR is stale only because its base branch moved, prefer a replacement PR
(author mode) over closing it.
