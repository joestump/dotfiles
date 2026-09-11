# Morning brief reference — queries

Every query writes to a file; print only capped `jq` projections.

    TOKEN="${GITEA_TOKEN:-$(cat /tmp/gitea-token 2>/dev/null)}"
    [ -n "$TOKEN" ] || echo "no gitea token"      # never print the value itself
    G=https://gitea.stump.rocks/api/v1
    H="Authorization: token $TOKEN"
    W=$(mktemp -d)
    SINCE=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)

## Step 1 — open PRs

    for u in joestump joestump-agent; do
      gh search prs --author="$u" --state=open --limit 20 --json repository,number,title,url,updatedAt,isDraft > "$W/gh-open-$u.json"
    done
    jq -s -r 'add | sort_by(.updatedAt) | reverse | .[:15][] | [.repository.nameWithOwner, .number, .isDraft, .title] | @tsv' "$W"/gh-open-*.json

    curl -sS -H "$H" "$G/repos/issues/search?type=pulls&state=open&limit=50" -o "$W/gitea-open.json"
    jq -r '.[] | select(.user.login == "joestump" or .user.login == "joestump-agent") | [.repository.full_name, .number, .updated_at, .title] | @tsv' "$W/gitea-open.json" | head -n 15

Per PR, only for the ones you will write a TL;DR for:

    gh pr view <n> --repo <o>/<r> --json mergeable,reviewDecision,statusCheckRollup \
      -q '[.mergeable, .reviewDecision, ([.statusCheckRollup[]?.conclusion] | unique | join(","))] | @tsv'
    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls/<n>" | jq -r '[.mergeable, .draft, .head.sha] | @tsv'
    curl -sS -H "$H" "$G/repos/<o>/<r>/commits/<sha>/status" | jq -r .state

## Step 2 — merged in the last 24 hours

    for u in joestump joestump-agent; do
      gh search prs --author="$u" --merged-at=">$SINCE" --limit 20 --json repository,number,title,url > "$W/gh-merged-$u.json"
    done
    jq -s -r 'add | .[:15][] | [.repository.nameWithOwner, .number, .title, .url] | @tsv' "$W"/gh-merged-*.json

    curl -sS -H "$H" "$G/repos/issues/search?type=pulls&state=closed&since=$SINCE&limit=50" -o "$W/gitea-closed.json"
    jq -r '.[] | select(.user.login == "joestump" or .user.login == "joestump-agent") | [.repository.full_name, .number, .title] | @tsv' "$W/gitea-closed.json" | head -n 15
    # the search hit has no merge flag — confirm each candidate
    curl -sS -H "$H" "$G/repos/<o>/<r>/pulls/<n>" | jq -r '[.merged, .merged_at, .html_url] | @tsv'

## Step 3 — issues created in the last 24 hours

    curl -sS -H "$H" "$G/repos/issues/search?type=issues&state=open&since=$SINCE&limit=50" -o "$W/gitea-issues.json"
    jq -r --arg s "$SINCE" '.[] | select(.created_at >= $s) | select(.user.login | test("renovate|bot"; "i") | not) | [.repository.full_name, .number, ([.labels[].name] | join(",")), .title] | @tsv' "$W/gitea-issues.json" | head -n 10

    for o in joestump joestump-agent stump-wtf tvdinner; do
      gh search issues --owner="$o" --created=">$SINCE" --state=open --limit 10 --json repository,number,title,url,labels > "$W/gh-issues-$o.json"
    done
    jq -s -r 'add | .[] | [.repository.nameWithOwner, .number, .title] | @tsv' "$W"/gh-issues-*.json | head -n 10

    # a body — for a suspected bug only
    curl -sS -H "$H" "$G/repos/<o>/<r>/issues/<n>" | jq -r .body | head -c 4000
    gh issue view <n> --repo <o>/<r> --json body -q .body | head -c 4000
