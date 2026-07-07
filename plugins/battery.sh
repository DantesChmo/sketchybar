#!/usr/bin/env bash

BATT_INFO="$(pmset -g batt)"
PERCENT="$(echo "$BATT_INFO" | grep -Eo '[0-9]+%' | tr -d '%')"
CHARGING="$(echo "$BATT_INFO" | grep -Eo 'AC Power')"

if [ -z "$PERCENT" ]; then
  exit 0
fi

COLOR=0xffffffff

if [ -n "$CHARGING" ]; then
  ICON="󰂄"
  COLOR=0xff9dd274
else
  case "$PERCENT" in
    100|9[0-9]) ICON="󰁹" ;;
    8[0-9])     ICON="󰂂" ;;
    7[0-9])     ICON="󰂁" ;;
    6[0-9])     ICON="󰂀" ;;
    5[0-9])     ICON="󰁿" ;;
    4[0-9])     ICON="󰁾" ;;
    3[0-9])     ICON="󰁽" ;;
    2[0-9])     ICON="󰁼" ;;
    1[0-9])     ICON="󰁻" ;;
    *)          ICON="󰁺"; COLOR=0xffed8796 ;;
  esac
fi

LABEL="$(printf '%3d%%' "$PERCENT")"

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
