#!/usr/bin/env bash

# Потребление RAM: (active + wired + compressed) / total — как «использовано» в Activity Monitor
PAGE_SIZE="$(vm_stat | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')"
TOTAL="$(sysctl -n hw.memsize)"
STATS="$(vm_stat)"

pages() { echo "$STATS" | sed -n "s/^$1: *\([0-9]*\)\./\1/p"; }
ACTIVE="$(pages 'Pages active')"
WIRED="$(pages 'Pages wired down')"
COMPRESSED="$(pages 'Pages occupied by compressor')"

if [ -z "$TOTAL" ] || [ -z "$PAGE_SIZE" ]; then
  exit 0
fi

USED=$(( (ACTIVE + WIRED + COMPRESSED) * PAGE_SIZE ))
PCT="$(awk -v u="$USED" -v t="$TOTAL" 'BEGIN { printf "%.0f", u * 100 / t }')"

COLOR=0xffffffff
if [ "$PCT" -ge 85 ]; then
  COLOR=0xffed8796
fi

LABEL="$(printf '%3d%%' "$PCT")"
sketchybar --set "$NAME" icon.color="$COLOR" label="$LABEL"
