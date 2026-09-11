# Issue sweep reference — triage and sizing

Carried from the full agent rules, which sweeps no longer load. Give every issue a
verdict before you give it a size.

## Verdicts

| Verdict | Meaning | Action |
|---|---|---|
| `OK` | Valid and actionable as written | Size it, leave it open |
| `STALE` | The work is already done | Close, with the evidence |
| `SUPERSEDED` | A design change made this issue describe something we deliberately did *not* build | Close, or rewrite it against the current design |
| `DUP` | Another issue covers it | Close, naming the survivor |
| `BLOCKED` | Real, but hard-gated on another issue | Leave open, name the blocker |
| `HUMAN` | No model can do it — physical access, a browser-only vendor signup, a personal decision, contacting someone | Leave open, flag it for Joe |
| `BOT` | Renovate Dependency Dashboards and similar | **Never size, never close.** They re-open themselves. |

## The evidence bar

**A merged PR saying `Closes #N` is not evidence that #N is fixed.** Neither is the
issue's age, and neither is a PR title that sounds right. The only evidence that work
is done is **the current state of the code on `main`** — go read it. In the 2026-08-25
triage, two issues a merged PR claimed to close were untouched: the exact wrong comment
was still in both files one of them named.

Issues also go stale **silently**: a PR that fixes the thing without a closing keyword
leaves the issue open forever. So scan recently merged PRs for work matching open
issues too — the check runs in both directions.

**Age is a prompt to look, never a reason to close.** Close on evidence, not a date.
No evidence within your per-issue budget? Leave it open and say why.

**Closing well:** comment before every close, and make the comment carry the evidence —
file and line, PR number, spec section — so the next reader can check your work. A
`412` on close means a recorded dependency; fix a wrong blocking link rather than
forcing past it. When an issue is only partly done, do not close it: say what shipped
and what remains, and leave it open scoped to the remainder.

## The size ladder

Every open issue in a repo we own carries **exactly one** `size/*` label. It answers one
question: what is the weakest model that can take this issue and carry it end to end —
read it, find the code, make the change, write the tests, and not get lost.

| Label | Anchor model | What lands here |
|---|---|---|
| `size/S` | an older Haiku | Mechanical and localized: docs, config, a rename, a dependency bump, a one-line fix whose location the issue names. No design judgment. |
| `size/M` | Opus 4.6 Max | One subsystem, a handful of files. The design is decided; the work is implementing and testing it. Bounded bug diagnosis. |
| `size/L` | Sonnet 5 | Spans subsystems or adds a component inside an established architecture: design within stated constraints, migrations, concurrency or protocol work. |
| `size/XL` | Opus 5 / Fable 5 | Epics, cross-repo or cross-service work, new architecture or security model, anything needing an ADR or spec first, or still ambiguous. |

Tie-breakers, in order:

- An `epic` label means `size/XL`, unless it is a thin tracking wrapper over children
  that are all `S` — then size it like its children.
- A long "Requirements" checklist pushes an issue up a bucket.
- Security-critical work, credential handling and data migrations push up a bucket.
- A well-written issue naming exact files and lines pulls down a bucket.

**One scale only.** `model/*`, `sonnet-ready` and friends are retired; two scales that
disagree are worse than none. Leave an existing `size/*` label alone unless it is
clearly wrong, and never size a `BOT` issue.
