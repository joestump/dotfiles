# Issue sweep reference — forge commands

Every listing goes to a file and is queried with `jq`, capped with `head`.

    TOKEN="${GITEA_TOKEN:-$(cat /tmp/gitea-token 2>/dev/null)}"
    [ -n "$TOKEN" ] || echo "no gitea token"      # never print the value itself
    G=https://gitea.stump.rocks/api/v1
    H="Authorization: token $TOKEN"
    W=$(mktemp -d)

## Gitea

    # repos in an org — paginate page=1,2,… until a page comes back empty
    curl -sS -H "$H" "$G/orgs/stump.wtf/repos?limit=50&page=1" -o "$W/repos.json"
    jq -r '.[] | [.full_name, .archived, .open_issues_count] | @tsv' "$W/repos.json"

    # open issues (not PRs) in one repo
    curl -sS -H "$H" "$G/repos/<o>/<r>/issues?state=open&type=issues&limit=50&page=1" -o "$W/issues.json"
    jq -r '.[] | [.number, ([.labels[].name] | join(",")), .updated_at, .title] | @tsv' "$W/issues.json" | head -n 60

    # one issue: the head of the body, then the last comments
    curl -sS -H "$H" "$G/repos/<o>/<r>/issues/<n>" | jq -r .body | head -c 3000
    curl -sS -H "$H" "$G/repos/<o>/<r>/issues/<n>/comments" | jq -r '.[-5:][] | [.user.login, .created_at, (.body | .[0:300])] | @tsv'

    # recently merged PRs, as evidence (issues also go stale silently)
    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls?state=closed&sort=recentupdate&limit=30" | jq -r '.[] | select(.merged) | [.number, .merged_at, .title] | @tsv'

    # comment (body in a file, footer included), then close
    jq -n --rawfile b "$W/body.md" '{body: $b}' | curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/issues/<n>/comments" -d @- | jq -r .html_url
    curl -sS -H "$H" -H 'Content-Type: application/json' -X PATCH "$G/repos/<o>/<r>/issues/<n>" -d '{"state":"closed"}' | jq -r .state

    # labels: list, create a missing size/* label, apply by id, remove by id
    curl -sS -H "$H" "$G/repos/<o>/<r>/labels?limit=50" | jq -r '.[] | [.id, .name] | @tsv'
    curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/labels" -d '{"name":"size/M","color":"#bf8700"}' | jq -r .id
    curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/<o>/<r>/issues/<n>/labels" -d '{"labels":[<id>]}' | jq -r '.[].name'
    curl -sS -H "$H" -X DELETE "$G/repos/<o>/<r>/issues/<n>/labels/<id>"

## GitHub

    gh repo view <o>/<r> --json isArchived -q .isArchived
    gh issue list --repo <o>/<r> --state open --limit 50 --json number,title,labels,updatedAt > "$W/gh.json"
    jq -r '.[] | [.number, ([.labels[].name] | join(",")), .updatedAt, .title] | @tsv' "$W/gh.json"
    gh issue view <n> --repo <o>/<r> --json body -q '.body[0:3000]'
    gh issue comment <n> --repo <o>/<r> --body-file "$W/body.md"
    gh issue close <n> --repo <o>/<r>
    gh label create size/M --repo <o>/<r> --color bf8700 2>/dev/null
    gh issue edit <n> --repo <o>/<r> --add-label size/M

Label colours: `size/S` 1a7f37 · `size/M` bf8700 · `size/L` d1242f · `size/XL` 8250df.
