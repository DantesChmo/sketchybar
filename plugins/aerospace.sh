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
    FS_ICON="$ICON_FULLSCREEN"
  else
    FS_ICON=""
  fi

  # Зоны фиксированной ширины (label.width задан в sketchybarrc), поэтому
  # пустой label занимает то же место, что и иконка — ничего не сдвигается.
  # Активная ячейка — инверсия: сплошная белая пилюля, чёрный текст.
  sketchybar --animate tanh 15 \
             --set ws.$1 background.color=0xffffffff \
             --set space.$1 label.color=0xff000000 \
             --set space.$1.mode label="$LAYOUT_ICON" label.color=0xff000000 \
             --set space.$1.fs label="$FS_ICON" label.color=0xff000000
else
  sketchybar --animate tanh 15 \
             --set ws.$1 background.color=0x22ffffff \
             --set space.$1 label.color=0x99ffffff \
             --set space.$1.mode label="" \
             --set space.$1.fs label=""
fi
