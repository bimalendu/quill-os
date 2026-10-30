#!/bin/sh
# Write the Quill wallpaper SVG for one variant and size.
# Usage: gen-wallpaper.sh light|dark WIDTH HEIGHT > out.svg
set -eu
variant=$1; W=$2; H=$3

if [ "$variant" = dark ]; then
    bg0=#0D0D22 bg1=#25236A blob1=#6665E3 blob2=#7E57FF mark=#FFFFFF mark_op=0.05 blob_op=0.30
else
    bg0=#F4F5FF bg1=#D3D6FF blob1=#4B4ACF blob2=#8A6BFF mark=#4B4ACF mark_op=0.07 blob_op=0.24
fi

# Blob and mark geometry follow the canvas size.
r1=$((W * 45 / 100)); r2=$((W * 40 / 100))
c1x=$((W * 80 / 100)); c1y=$((H * 15 / 100))
c2x=$((W * 12 / 100)); c2y=$((H * 90 / 100))
# The feather mark: 256-unit glyph scaled to ~85% of the height, bottom right.
scale=$(awk -v h="$H" 'BEGIN { printf "%.4f", h * 0.85 / 256 }')
mx=$((W - H * 85 / 100 - W * 6 / 100)); my=$((H * 10 / 100))

cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$bg0"/>
      <stop offset="1" stop-color="$bg1"/>
    </linearGradient>
    <radialGradient id="b1"><stop offset="0" stop-color="$blob1" stop-opacity="$blob_op"/><stop offset="1" stop-color="$blob1" stop-opacity="0"/></radialGradient>
    <radialGradient id="b2"><stop offset="0" stop-color="$blob2" stop-opacity="$blob_op"/><stop offset="1" stop-color="$blob2" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="$W" height="$H" fill="url(#bg)"/>
  <circle cx="$c1x" cy="$c1y" r="$r1" fill="url(#b1)"/>
  <circle cx="$c2x" cy="$c2y" r="$r2" fill="url(#b2)"/>
  <g transform="translate($mx $my) scale($scale)" opacity="$mark_op" fill="$mark">
    <path d="M210 42C126 46 74 100 66 192C150 186 206 130 210 42Z"/>
    <path fill="none" stroke="$mark" stroke-width="8" stroke-linecap="round" d="M56 214L90 176"/>
  </g>
</svg>
SVG
