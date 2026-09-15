#!/usr/bin/env bash
# Regenerate the PNG notification icons from their SVG sources. The PNGs are
# committed (notifiers like notify-send / terminal-notifier want a raster), so
# this is a dev-only helper — run it after editing a source SVG or colour.
#
# Three 128x128 RGBA families are produced:
#   agent-<state>.png          state dots — the ⚪🟡🔴🟢 traffic light ({icon_path})
#   logo-<agent>.png           per-agent brand mark on a coloured circle ({agent_icon_path})
#   badge-<agent>-<state>.png  agent mark + a corner state dot ({badge_path})
#
# Agent marks are the projects' own logos (see CREDITS.md for sources); the
# circle tile + state dot are drawn here so the set stays a coherent family.
#
# Requires rsvg-convert (librsvg) and ImageMagick 7 (magick):
#   macOS:  brew install librsvg imagemagick
#   Debian: apt install librsvg2-bin imagemagick
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v rsvg-convert >/dev/null 2>&1 || { echo "rsvg-convert not found (brew install librsvg)"; exit 1; }
command -v magick       >/dev/null 2>&1 || { echo "magick (ImageMagick 7) not found (brew install imagemagick)"; exit 1; }

OUT=128       # final icon size
S=256         # supersample, then downscale for clean anti-aliased edges
STATES="wait done busy idle"
AGENTS="claude opencode pi"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# state dot fill — must match the circle drawn in agent-<state>.svg
state_color() { case "$1" in
  wait) echo "#DD2E44" ;; done) echo "#78B159" ;;
  busy) echo "#FDCB58" ;; *)    echo "#E6E7E8" ;; esac; }

# a filled circle with a faint ring, drawn at supersample size
tile() { # <fill> <ring-rgba> <out>
  magick -size ${S}x${S} xc:none \
    -fill "$1"    -draw "circle $((S/2)),$((S/2)) $((S/2)),16" \
    -fill none -stroke "$2" -strokewidth 4 -draw "circle $((S/2)),$((S/2)) $((S/2)),16" "$3"
}
# clip anything outside the circle (used after compositing a mark on)
clip() { magick "$1" \( -size ${S}x${S} xc:none -fill white \
  -draw "circle $((S/2)),$((S/2)) $((S/2)),16" \) -alpha set -compose DstIn -composite "$1"; }

# --- state dots: flat SVG -> PNG -------------------------------------------
for st in $STATES; do
  rsvg-convert -w "$OUT" -h "$OUT" "agent-$st.svg" -o "agent-$st.png"
  echo "  agent-$st.png"
done

# --- per-agent brand mark on a coloured circle -----------------------------
# Emits a supersampled $tmp/logo-<agent>.png (reused for badges) + logo-<agent>.png.
build_logo() { # <agent>
  local agent="$1"
  local big="$tmp/logo-$agent.png" mark="$tmp/$agent-mark.png"
  rsvg-convert -w "$S" -h "$S" "logo-$agent.svg" -o "$mark"
  case "$agent" in
    claude)  # terracotta tile, mark recoloured white
      magick "$mark" -channel RGB -fill white -colorize 100% +channel "$mark"
      tile "#D97757" "#00000026" "$big"
      magick "$big" \( "$mark" -resize 150x150 \) -gravity center -compose over -composite "$big"
      clip "$big" ;;
    pi)      # white tile, mark kept as-is (black)
      tile "#FFFFFF" "#00000026" "$big"
      magick "$big" \( "$mark" -resize 132x132 \) -gravity center -compose over -composite "$big"
      clip "$big" ;;
    opencode)  # favicon already carries its own dark tile — just circle-crop
      magick "$mark" -resize ${S}x${S} "$big"; clip "$big"
      magick "$big" -fill none -stroke "#ffffff26" -strokewidth 4 \
        -draw "circle $((S/2)),$((S/2)) $((S/2)),16" "$big" ;;
    *) echo "no treatment defined for agent '$agent'"; return 1 ;;
  esac
  magick "$big" -resize ${OUT}x${OUT} "logo-$agent.png"
  echo "  logo-$agent.png"
}

# --- badge: agent circle + a corner state dot (white ring for separation) --
build_badge() { # <agent> <state>
  local agent="$1" st="$2"
  magick "$tmp/logo-$agent.png" \
    -fill white           -draw "circle 196,196 196,144" \
    -fill "$(state_color "$st")" -draw "circle 196,196 196,152" \
    -resize ${OUT}x${OUT} "badge-$agent-$st.png"
  echo "  badge-$agent-$st.png"
}

for agent in $AGENTS; do
  build_logo "$agent"
  for st in $STATES; do build_badge "$agent" "$st"; done
done
