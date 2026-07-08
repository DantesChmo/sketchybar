#!/usr/bin/env bash

# Nerd Font глифы задаём через коды, а не литералами:
# символы из Private Use Area, поэтому генерируем их printf'ом.
ICON_COLUMNS=$(printf '')    # nf-fa-columns   — h_tiles
ICON_ROWS=$(printf '')       # nf-fa-bars      — v_tiles
ICON_STACK=$(printf '')      # nf-fa-clone     — accordion
ICON_FULLSCREEN=$(printf '') # nf-fa-expand    — fullscreen

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  LAYOUT=$(aerospace list-workspaces --focused --format '%{workspace-root-container-layout}' 2>/dev/null | tr -d '[:space:]')
  FULLSCREEN=$(aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null | tr -d '[:space:]')

  case "$LAYOUT" in
    *accordion*) LAYOUT_ICON="$ICON_STACK" ;;
    v_tiles)     LAYOUT_ICON="$ICON_ROWS" ;;
    h_tiles)     LAYOUT_ICON="$ICON_COLUMNS" ;;
    *)           LAYOUT_ICON="$LAYOUT" ;;
  esac

  if [ "$FULLSCREEN" = "true" ]; then
    FS_ICON=" $ICON_FULLSCREEN"
  else
    FS_ICON=""
  fi

  sketchybar --set $NAME background.drawing=on label="$1 ${LAYOUT_ICON}${FS_ICON}"
else
  sketchybar --set $NAME background.drawing=off label="$1"
fi
