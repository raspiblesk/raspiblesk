#!/bin/bash
# Generate RaspiBlesk startup PNG images using ImageMagick
# Sizes: startlogo = 480x320, splash = 1024x768
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FONT_BOLD="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_NORM="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

BG="#090e1a"
BORDER="#1e2d4a"
GOLD="#c8962a"
YELLOW="#ffe000"
DIM="#7a8baa"
WHITE="#e4e8f4"

# Lightning bolt polygon for 480x320
BOLT_480="polygon 256,55 204,168 238,168 208,272 272,152 236,152"

# Lightning bolt polygon for 1024x768
BOLT_1024="polygon 542,110 440,360 514,360 442,580 578,324 502,324"

make_startlogo() {
  local idx="$1"
  local subtitle="$2"
  local out="${SCRIPT_DIR}/startlogo${idx}.png"

  convert -size 480x320 "xc:${BG}" \
    -fill "${BORDER}" -draw "rectangle 0,0 479,319" \
    -fill "${BG}"     -draw "rectangle 4,4 475,315" \
    -fill "${YELLOW}" -draw "${BOLT_480}" \
    -font "${FONT_BOLD}" -pointsize 54 \
    -fill "${GOLD}" -gravity Center -annotate +0-28 "RaspiBlesk" \
    -font "${FONT_NORM}" -pointsize 16 \
    -fill "${DIM}"  -gravity Center -annotate +0+52 "${subtitle}" \
    "${out}"
  echo "  → ${out}"
}

make_splash() {
  local out="${SCRIPT_DIR}/splash.png"

  convert -size 1024x768 "xc:${BG}" \
    -fill "${BORDER}" -draw "rectangle 0,0 1023,767" \
    -fill "${BG}"     -draw "rectangle 8,8 1015,759" \
    -fill "${YELLOW}" -draw "${BOLT_1024}" \
    -font "${FONT_BOLD}" -pointsize 110 \
    -fill "${GOLD}" -gravity Center -annotate +0-60 "RaspiBlesk" \
    -font "${FONT_NORM}" -pointsize 32 \
    -fill "${DIM}"  -gravity Center -annotate +0+80 "Permanent Proof Network" \
    "${out}"
  echo "  → ${out}"
}

echo "Generating RaspiBlesk startup images..."

make_startlogo 0 "Permanent Proof Network"
make_startlogo 1 "Starting your node..."
make_startlogo 2 "Syncing the chain..."
make_startlogo 3 "Lightning ready"
make_startlogo 4 "Permanent Proof Network"
make_startlogo 5 "Your node is starting..."
make_startlogo 6 "Verifying the ledger..."
make_startlogo 7 "Connecting to the network..."

echo "Generating boot splash (1024x768)..."
make_splash

echo "Done. All images in ${SCRIPT_DIR}/"
