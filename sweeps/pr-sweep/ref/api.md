# PR sweep reference — forge commands

Read this when you need a command. Every listing goes to a file first and is
queried with `jq`; nothing here should put more than ~60 lines into your
context.

## Auth and scratch space

    TOKEN="${GITEA_TOKEN:-$(cat /tmp/gitea-token 2>/dev/null)}"
    [ -n "$TOKEN" ] || echo "no gitea token"      # never print the value itself
    G=https://gitea.stump.rocks/api/v1
    H="Authorization: token $TOKEN"
    W=$(mktemp -d)

GitHub: `gh` is already logged in as this box's identity. If a git push to
github.com fails on auth, record it and move on.

## Enumerate — Gitea

    # PRs you authored, across every repo you can see
    curl -sS -H "$H" "$G/repos/issues/search?type=pulls&state=open&created=true&limit=50" -o "$W/mine.json"
    jq -r '.[] | [.repository.full_name, .number, .updated_at, .title] | @tsv' "$W/mine.json" | head -n 40
    # PRs the sibling authored
    curl -sS -H "$H" "$G/repos/issues/search?type=pulls&state=open&limit=50&posters=<sibling>" -o "$W/sibling.json"
    # archived? (check once per repo)
    curl -sS -H "$H" "$G/repos/<owner>/<repo>" | jq -r .archived

## Enumerate — GitHub

    gh search prs --author=<login> --state=open --limit 30 --json repository,number,title,url,isDraft,updatedAt > "$W/gh.json"
    jq -r '.[] | [.repository.nameWithOwner, .number, .isDraft, .title] | @tsv' "$W/gh.json"
    gh repo view <owner>/<repo> --json isArchived -q .isArchived

## One PR — state, feedback, CI

Gitea:

    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls/<n>" -o "$W/pr.json"
    jq -r '[.head.sha, .mergeable, .draft, .base.ref] | @tsv' "$W/pr.json"
    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls/<n>/reviews" | jq -r '.[] | [.user.login, .state, .submitted_at] | @tsv'
    curl -sS -H "$H" "$G/repos/<o>/<r>/issues/<n>/comments" -o "$W/c.json"
    jq -r '.[-10:][] | [.user.login, .created_at, (.body | .[0:300])] | @tsv' "$W/c.json"
    curl -sS -H "$H" "$G/repos/<o>/<r>/commits/<sha>/status" | jq -r '.state, (.statuses[] | [.status, .context] | @tsv)'

GitHub:

    gh pr view <n> --repo <o>/<r> --json mergeable,mergeStateStatus,reviewDecision,headRefOid,isDraft
    gh pr checks <n> --repo <o>/<r>
    gh api repos/<o>/<r>/pulls/<n>/comments --jq '.[-10:][] | [.user.login, .created_at, (.body | .[0:300])] | @tsv'

CI logs — the tail of the failing job, never the whole log:

    gh run view <run-id> --repo <o>/<r> --log-failed | tail -n 80

## Diffs — stat first, then one file at a time

    gh pr diff <n> --repo <o>/<r> --name-only
    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls/<n>.diff" -o "$W/pr.diff"
    git apply --stat "$W/pr.diff" | tail -n 40
    awk -v f="path/to/file" '/^diff --git/{p = index($0, " a/" f " ") > 0} p' "$W/pr.diff" | head -n 200

## Comment, review, merge, close

Write every multi-line body to `$W/body.md` first, footer included; it keeps
quoting sane.

Gitea:

    jq -n --rawfile b "$W/body.md" '{body: $b}' | curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/issues/<n>/comments" -d @- | jq -r .html_url
    # review event: APPROVED | REQUEST_CHANGES | COMMENT
    jq -n --rawfile b "$W/body.md" '{body: $b, event: "APPROVED"}' | curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/pulls/<n>/reviews" -d @- | jq -r .state
    # merge now, or merge when checks succeed (auto-merge)
    curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/pulls/<n>/merge" -d '{"Do":"squash"}'
    curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/pulls/<n>/merge" -d '{"Do":"squash","merge_when_checks_succeed":true}'
    curl -sS -H "$H" -H 'Content-Type: application/json' -X PATCH "$G/repos/<o>/<r>/pulls/<n>" -d '{"state":"closed"}' | jq -r .state

GitHub:

    gh pr comment <n> --repo <o>/<r> --body-file "$W/body.md"
    gh pr review <n> --repo <o>/<r> --approve --body-file "$W/body.md"
    gh pr merge <n> --repo <o>/<r> --squash
    gh pr merge <n> --repo <o>/<r> --auto --squash
    gh pr close <n> --repo <o>/<r> --comment "<reason and footer>"

## joestump/dotfiles

Tier B: the owner is `joestump`, so an APPROVED review is required before a
merge, even though both identities work in it. After a merge into `main`, run
`czu` on this box so the change is actually applied. If you run from a fork
(origin=joestump-agent/dotfiles, upstream=joestump/dotfiles), keep the fork's
`main` in step afterwards: fetch upstream, fast-forward, push to origin. A fix
that means editing the dotfiles needs the `chezmoi` skill, which a sweep does
not load — hold it and say so in the summary instead.
