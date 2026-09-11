# StumpCloud sweep reference — handoff issues and OMGs

    TOKEN="${GITEA_TOKEN:-$(cat /tmp/gitea-token 2>/dev/null)}"
    [ -n "$TOKEN" ] || echo "no gitea token"      # never print the value itself
    G=https://gitea.stump.rocks/api/v1
    H="Authorization: token $TOKEN"
    W=$(mktemp -d)

## Before filing: look for a duplicate

    curl -sS -H "$H" "$G/repos/stumpcloud/stumpcloud/issues?state=open&type=issues&q=<host or service>&limit=20" \
      | jq -r '.[] | [.number, ([.labels[].name] | join(",")), .title] | @tsv'

## File a handoff issue

Write the body to `$W/body.md` first: host, service, symptom, the log line that
identified it, the repo and file you believe is wrong, and what you already
ruled out. That body is the entire handoff.

    jq -n --arg t "<title>" --rawfile b "$W/body.md" '{title: $t, body: $b}' \
      | curl -sS -H "$H" -H 'Content-Type: application/json' -X POST "$G/repos/stumpcloud/stumpcloud/issues" -d @- \
      | jq -r .html_url

Leave it unlabelled for triage, unless it is an OMG action item.

## OMGs — file new incidents only

A real outage outlives one run. Filing on severity alone buries the real
incidents under a fresh postmortem every day. Before filing an OMG:

1. List the children of the OMGs parent document in the StumpCloud collection in
   Outline.
2. List open `OMG` issues:
   `curl -sS -H "$H" "$G/repos/stumpcloud/stumpcloud/issues?state=open&type=issues&labels=OMG&limit=50" | jq -r '.[] | [.number, .title] | @tsv'`
3. Every OMG action item links its Outline doc, so that URL is the exact dedupe
   key — prefer it over matching symptom text.

Then:

- **Already covered, still broken:** do not file again. Append to that OMG's
  timeline, keep its status callout open, add an action item only for something
  genuinely new, and call it a continuation (with the link) in the summary.
- **Already covered, now resolved:** mark the OMG resolved, and close the action
  items your remediation actually fixed.
- **New:** file it with the `stumpcloud-omg` skill — this standing instruction
  is the operator's approval, so do not wait for a human — then file its action
  items as `OMG`-labelled issues.
