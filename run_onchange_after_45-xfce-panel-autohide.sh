#!/usr/bin/env bash
# Make the XFCE bottom panel auto-hide (reveal on hover) and horizontally centered.
#
# chezmoi run_onchange_ script: reruns whenever this file's content changes, so
# tweaking the values below and `chezmoi apply` re-asserts them. Idempotent and
# best-effort — silently skips on non-XFCE machines and headless (no-DISPLAY) runs.
#
# Everything machine-specific is derived at apply time rather than hardcoded:
#   * the bottom panel is detected (bottom-most by y), not assumed to be panel-2
#   * the centered x is computed from the live screen width
#   * the vertical position (p= snap and y) is read from the machine's own config
# so nothing here is tied to the 1512x949 RDP box this was first set up on.
set -euo pipefail

# Needs a running X session + xfconfd; bail cleanly otherwise.
[ -n "${DISPLAY:-}" ] || { echo "no DISPLAY; skipping xfce-panel autohide"; exit 0; }
command -v xfconf-query >/dev/null 2>&1 || { echo "no xfconf-query; skipping (not XFCE)"; exit 0; }
xfconf-query -c xfce4-panel -p /panels -l >/dev/null 2>&1 || { echo "no xfce4-panel channel; skipping"; exit 0; }

# Find the bottom-most horizontal panel by parsing each panel's y coordinate
# out of its "p=<snap>;x=<x>;y=<y>" position string.
bottom_panel=""
bottom_y=-1
while read -r node; do
  case "$node" in */position) ;; *) continue ;; esac
  panel="${node#/panels/}"; panel="${panel%/position}"
  pos="$(xfconf-query -c xfce4-panel -p "/panels/$panel/position" 2>/dev/null || true)"
  y="$(printf '%s\n' "$pos" | sed -n 's/.*;y=\([0-9]\+\).*/\1/p')"
  [ -n "$y" ] || continue
  if [ "$y" -gt "$bottom_y" ]; then bottom_y="$y"; bottom_panel="$panel"; fi
done < <(xfconf-query -c xfce4-panel -p /panels -l 2>/dev/null | grep '/position$')

[ -n "$bottom_panel" ] || { echo "no bottom panel found; skipping"; exit 0; }

# Screen width from the first connected output (fallback 1920).
width="$(xrandr 2>/dev/null | awk '/ connected/{ for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) { split($i,a,"x"); print a[1]; exit } }')"
center=$(( ${width:-1920} / 2 ))

# Preserve the machine's own snap (p=) and vertical (y=); only rewrite x= to center.
pos="$(xfconf-query -c xfce4-panel -p "/panels/$bottom_panel/position")"
p="$(printf '%s\n' "$pos" | sed -n 's/.*p=\([0-9]\+\).*/\1/p')"
y="$(printf '%s\n' "$pos" | sed -n 's/.*;y=\([0-9]\+\).*/\1/p')"

xfconf-query -c xfce4-panel -p "/panels/$bottom_panel/autohide-behavior" -s 2
xfconf-query -c xfce4-panel -p "/panels/$bottom_panel/position" -s "p=${p:-12};x=${center};y=${y:-0}"

echo "xfce-panel: $bottom_panel autohide=always, centered x=$center (screen ${width:-?}px)"

# Reload so it takes effect now (best-effort; harmless if it fails).
xfce4-panel -r >/dev/null 2>&1 || true
