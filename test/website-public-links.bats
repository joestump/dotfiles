#!/usr/bin/env bats
# website/ is published to GitHub Pages (https://joestump.github.io/dotfiles/) as
# well as the internal Gitea Pages copy, so every link on it is read by people
# who cannot reach gitea.stump.rocks at all. base.md's "Never link Gitea in
# anything public" rule names public docs sites explicitly; issue #178 found four
# such links still on the site months after the rule landed, which is exactly the
# silent regression a check exists to stop.
#
# The rule is about LINKS, not mentions: naming the internal host in prose, in a
# `chezmoi init --apply <url>` command, in a Go module path or in a mermaid node
# label is allowed (and unavoidable — those commands have to work). So this only
# fails on things a reader can actually click:
#
#   * a markdown link whose target is Gitea            ]( https://gitea… )
#   * a bare https:// URL in prose, which GFM autolinks
#   * an href/editUrl in the Docusaurus config or a page component
#
# Fenced code blocks (including blockquoted ones) and inline code spans are
# stripped before the check for that reason.
load test_helper

# Emit every markdown line with fenced blocks and inline code removed.
prose_only() {
  awk '
    { line = $0
      sub(/^[[:space:]]*>[[:space:]]?/, "", line)   # unwrap blockquotes
      if (line ~ /^[[:space:]]*```/) { fence = !fence; next }
      if (fence) next
      gsub(/`[^`]*`/, "", line)                     # drop inline code spans
      print FILENAME ":" FNR ":" line
    }
  ' "$@"
}

@test "no clickable Gitea links in the published docs" {
  local files hits
  # Filter by extension rather than by pathspec glob: git's `*` matches slashes,
  # so `website/**/*.md` silently skips top-level files like website/README.md.
  files="$(cd "$REPO_ROOT" && git ls-files 'website/' | grep -E '\.mdx?$')"
  [ -n "$files" ]

  cd "$REPO_ROOT"
  # shellcheck disable=SC2086
  hits="$(prose_only $files | grep -E '\]\([^)]*gitea\.stump\.rocks|https?://gitea\.stump\.rocks' || true)"

  if [ -n "$hits" ]; then
    echo "Gitea links on the public docs site — point them at the GitHub mirror," >&2
    echo "or name the repo in plain text and say the source is private:" >&2
    echo "$hits" >&2
    return 1
  fi
}

@test "no Gitea links in the site chrome (navbar, footer, edit links)" {
  local hits
  cd "$REPO_ROOT"
  hits="$(git ls-files 'website/' | grep -E '\.jsx?$' \
    | xargs -r grep -nE '(href|editUrl|to)[[:space:]]*:[^,]*gitea\.stump\.rocks' || true)"

  if [ -n "$hits" ]; then
    echo "Gitea links in the site chrome — these render on every page:" >&2
    echo "$hits" >&2
    return 1
  fi
}
