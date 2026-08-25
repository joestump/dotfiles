#!/usr/bin/env bash
# ShellCheck — Plain Scripts And Rendered Chezmoi Templates
#
# `make lint` used to shellcheck only the plain `*.sh` files. Every apply-time
# script in `.chezmoiscripts/` is a `*.sh.tmpl`, so the glob missed all of them
# locally — a developer's green `make lint` said nothing about the scripts that
# actually run on every `chezmoi apply` on every node. CI had a render-based
# step, but it lived only in `.gitea/workflows/ci.yml`, so local and CI could
# disagree; and it piped `chezmoi execute-template` into `shellcheck` with no
# `pipefail`, so a template that failed to render fed shellcheck an empty stdin
# and passed clean. This script is that step, done once, called from both.
#
# Templates are gated on two axes — `.chezmoi.os` (darwin vs linux) and the
# `-agent` login suffix — so any single render covers only one branch of each.
# Rendering once per combination is what makes the coverage real: on a Mac the
# linux branches were invisible, and in CI (ubuntu) the darwin branches were.
# Renders that come out identical across variants are deduplicated by content
# hash, so a finding in un-gated code is reported once and not four times.
#
# Deliberately bash 3.2-compatible (no mapfile, no associative arrays): a Mac
# without Homebrew bash still has to be able to run `make lint`.
#
# @joestump-agent 08/25/2026 - Extracted from the Makefile and the CI lint job,
# added the render matrix, and made a failed or empty render a hard error
# instead of a silent pass.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# SC1091 stays off everywhere: sourced libraries resolve to destination paths
# (~/.config/dotfiles/ui-lib.sh) that exist neither in the source tree nor in
# the render output, so "not following" is noise rather than a finding.
SHELLCHECK_ARGS="-x -e SC1091"

fail=0

# The plain, non-template scripts. `*.sh` covers every tracked shell file today
# (checked against the hand-maintained glob it replaces) and keeps covering new
# directories without another Makefile edit. `.githooks/pre-commit` has no
# extension, so it is named explicitly. No tracked path contains a space, so
# word-splitting the list is safe here.
echo "==> shellcheck — plain scripts"
# shellcheck disable=SC2086 # SHELLCHECK_ARGS and the file list must word-split.
git ls-files '*.sh' '.githooks/pre-commit' | xargs -r shellcheck $SHELLCHECK_ARGS || fail=1

templates=$(git ls-files '*.sh.tmpl')
if [ -z "$templates" ]; then
  echo "==> shellcheck — rendered templates: none tracked"
  exit "$fail"
fi

# The render matrix. Each entry is `name<TAB>override-data-json`, passed to
# `chezmoi execute-template --override-data` so one machine can render the
# branch it is not. `agentIdentity` is what the `-agent` gates actually read
# (`.agentIdentity | default .chezmoi.username`), so setting it exercises both
# roles without overriding chezmoi's builtin username.
variants='darwin-human	{"chezmoi":{"os":"darwin"},"agentIdentity":"lintuser"}
darwin-agent	{"chezmoi":{"os":"darwin"},"agentIdentity":"lintuser-agent"}
linux-human	{"chezmoi":{"os":"linux"},"agentIdentity":"lintuser"}
linux-agent	{"chezmoi":{"os":"linux"},"agentIdentity":"lintuser-agent"}'

render_root=$(mktemp -d)
trap 'rm -rf "$render_root"' EXIT

hashes="$render_root/.seen"
: >"$hashes"
targets="$render_root/.targets"
: >"$targets"

n_tmpl=$(printf '%s\n' "$templates" | wc -l | tr -d ' ')
n_var=$(printf '%s\n' "$variants" | wc -l | tr -d ' ')
echo "==> shellcheck — rendered chezmoi templates ($n_tmpl templates x $n_var variants)"

while IFS="$(printf '\t')" read -r name data; do
  for tmpl in $templates; do
    out="$render_root/$name/${tmpl%.tmpl}"
    mkdir -p "$(dirname "$out")"

    # Hard-fail on a render error. The CI step this replaces piped straight
    # into shellcheck, where a chezmoi failure was hidden by the pipeline's
    # exit status and the resulting empty document linted clean.
    if ! chezmoi execute-template --source "$repo_root" --override-data "$data" \
        <"$tmpl" >"$out"; then
      echo "::error::render failed [$name] $tmpl" >&2
      fail=1
      continue
    fi
    if [ ! -s "$out" ]; then
      echo "::error::rendered empty [$name] $tmpl" >&2
      fail=1
      continue
    fi

    hash=$(shasum -a 256 <"$out" | cut -d' ' -f1)
    if grep -qxF "$hash" "$hashes"; then
      continue
    fi
    printf '%s\n' "$hash" >>"$hashes"
    printf '%s\n' "$name/${tmpl%.tmpl}" >>"$targets"
  done
done <<EOF
$variants
EOF

echo "    $(wc -l <"$targets" | tr -d ' ') unique renderings after dedup"

# Run from the render root so a finding names its variant and source template:
# `linux-agent/.chezmoiscripts/run_after_30-install-crush.sh`.
# shellcheck disable=SC2086 # SHELLCHECK_ARGS must word-split.
(cd "$render_root" && xargs -r shellcheck $SHELLCHECK_ARGS <"$targets") || fail=1

exit "$fail"
