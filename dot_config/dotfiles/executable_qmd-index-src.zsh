#!/usr/bin/env zsh
# qmd-index-src.zsh — index ~/src into qmd, one collection per top-level repo.
#
# Single source of truth for "qmd over ~/src", called by:
#   - the chezmoi apply hook (.chezmoiscripts/run_onchange_after_49-qmd-index-src.sh)
#   - the `dot` menu → "Re-index ~/src (qmd)" and the `status` panel (read-only)
# One implementation means an interactive re-index behaves exactly like the one
# that runs on `chezmoi apply` / `czu`.
#
# Behaviour:
#   - No-op (exit 0) when ~/src is absent or qmd isn't installed — this box may
#     not be a dev box, and a missing optional tool must never be fatal.
#   - For each top-level dir under ~/src that contains at least one markdown file,
#     ensure a qmd collection named after the dir exists (create if missing), then
#     `qmd update` to (re)index every collection. Dirs with zero markdown are
#     skipped so the index doesn't fill with empty collections.
#   - Does NOT run `qmd embed` — the ~2GB GGUF models + compute are opt-in, exactly
#     like install-qmd.sh which refuses to pre-warm them. BM25 (lex) search works
#     immediately; run `qmd embed` yourself to enable semantic (vec) search.
emulate -L zsh
setopt no_nomatch          # an empty ~/src/*/ glob must not abort the loop

# Match czu-run: give the scheduled/headless path a sane PATH so `qmd` resolves.
export PATH="$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Clean progress via the shared UI lib (heading + ticked items — gum on a TTY,
# plain lines otherwise), so an on-apply index reads like every other czu phase.
# zsh fallback keeps the runner working if the lib hasn't been applied yet.
. "$HOME/.config/dotfiles/ui-lib.sh" 2>/dev/null || {
  have() { command -v "$1" >/dev/null 2>&1 }
  heading() { print -r -- ""; print -r -- "== $* ==" }
  item() { shift; print -r -- "    - $*" }
  warn() { print -u2 -- "  WARN: $*" }
}

SRC="$HOME/src"
heading "🔎 qmd index"
[[ -d "$SRC" ]] || { item dim "no $SRC — nothing to index"; exit 0 }
command -v qmd >/dev/null 2>&1 || { item dim "qmd not installed — skipping"; exit 0 }

# Snapshot existing collections once so the add-if-missing check is a cheap
# substring match (a collection prints as "name (qmd://name/)").
local existing; existing="$(qmd collection list 2>/dev/null)"

local -a added skipped
local d name
for d in "$SRC"/*(/N); do          # (/N): directories only, null glob if none
  name="${d:t}"                     # basename of the top-level dir

  # Already a collection? Leave it — `qmd update` below refreshes it.
  if [[ "$existing" == *"qmd://${name}/"* ]]; then
    continue
  fi

  # Only index dirs that actually contain markdown; skip node_modules/.git while
  # probing so a big JS repo with no docs doesn't get walked in full.
  if ! find "$d" \( -name .git -o -name node_modules \) -prune -o -type f -name '*.md' -print -quit 2>/dev/null | grep -q .; then
    skipped+="$name"
    continue
  fi

  if ( cd "$d" && qmd collection add . >/dev/null 2>&1 ); then
    item ok "added collection ${name}"
    added+="$name"
  else
    warn "failed to add collection '${name}' (continuing)"
  fi
done

# Refresh every collection (incremental — only changed files are re-read).
qmd update >/dev/null 2>&1 || warn "'qmd update' returned non-zero"

item ok "${#added} added, ${#skipped} skipped (no markdown)"
(( ${#skipped} )) && item dim "skipped: ${skipped[*]}"
exit 0
