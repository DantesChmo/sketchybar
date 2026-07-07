#!/usr/bin/env bash

# Второй сэмпл top даёт корректную загрузку CPU (первый — усреднение с загрузки)
LINE="$(top -l 2 -n 0 -s 1 | grep -E '^CPU usage' | tail -1)"
IDLE="$(echo "$LINE" | grep -Eo '[0-9.]+% idle' | grep -Eo '[0-9.]+')"

if [ -z "$IDLE" ]; then
  exit 0
fi

PCT="$(awk -v i="$IDLE" 'BEGIN { p = 100 - i; if (p < 0) p = 0; printf "%.0f", p }')"

COLOR=0xffffffff
if [ "$PCT" -ge 85 ]; then
  COLOR=0xffed8796
fi

LABEL="$(printf '%3d%%' "$PCT")"
sketchybar --set "$NAME" icon.color="$COLOR" label="$LABEL"
