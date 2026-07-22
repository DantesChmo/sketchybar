#!/usr/bin/env bash

# Единый хендлер ячейки воркспейса. Вызывается тремя способами:
#   aerospace.sh <sid>              — рендер по событию (aerospace_workspace_change,
#                                     mouse.entered/exited с bracket'а — по $SENDER)
#   aerospace.sh <sid> click:<zone> — клик по зоне (num | fs | mode)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SID="$1"

# Nerd Font глифы задаём escape-кодами, а не литералами: символы из
# Private Use Area невидимы в редакторе и легко теряются при правках.
ICON_COLUMNS=$(printf '\xef\x83\x9b')    # U+F0DB nf-fa-columns — h_tiles
ICON_ROWS=$(printf '\xef\x83\x89')       # U+F0C9 nf-fa-bars    — v_tiles
ICON_STACK=$(printf '\xef\x89\x8d')      # U+F24D nf-fa-clone   — accordion
ICON_FULLSCREEN=$(printf '\xef\x81\xa5') # U+F065 nf-fa-expand  — fullscreen

focused_ws() { aerospace list-workspaces --focused 2>/dev/null | tr -d '[:space:]'; }

# Для ховера спрашивать aerospace слишком медленно (~50мс на событие мыши) —
# берём фокус из кеша, который рендер обновляет при каждом переключении.
focused_ws_cached() { cat /tmp/sketchybar_focused_ws 2>/dev/null || focused_ws; }

case "${2:-$SENDER}" in
  click:*)
    ZONE="${2#click:}"
    FOCUSED=$(focused_ws)
    if [ "$SID" != "$FOCUSED" ]; then
      # Чужой воркспейс — любая зона просто переключает на него
      aerospace workspace "$SID"
      exit 0
    fi
    case "$ZONE" in
      fs) aerospace fullscreen off 2>/dev/null ;;
      mode)
        # Цикл считаем сами: встроенное `aerospace layout a b c` шагает криво.
        # h_tiles -> v_tiles -> accordion -> h_tiles
        CUR=$(aerospace list-workspaces --focused --format '%{workspace-root-container-layout}' 2>/dev/null | tr -d '[:space:]')
        case "$CUR" in
          h_tiles)     aerospace layout v_tiles ;;
          v_tiles)     aerospace layout h_accordion ;;
          *accordion*) aerospace layout h_tiles ;;
          *)           aerospace layout h_tiles ;;
        esac
        ;;
    esac
    # Layout/фулскрин меняются без workspace-change ивента — дёргаем перерисовку сами
    sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE="$FOCUSED"
    ;;

  mouse.entered)
    # Ховер подсвечивает пилюлю целиком; активную не трогаем — она уже инвертирована
    [ "$SID" = "$(focused_ws_cached)" ] && exit 0
    sketchybar --animate tanh 10 --set ws.$SID background.color=0x44ffffff
    ;;

  mouse.exited)
    [ "$SID" = "$(focused_ws_cached)" ] && exit 0
    # Зоны пилюли — три отдельных айтема, и переход мыши между ними тоже даёт
    # exited. Гасим только если курсор реально ушёл за прямоугольник пилюли —
    # позицию мыши отдаёт helper, порядок прихода событий не важен.
    HELPER="${CONFIG_DIR:-$HOME/.config/sketchybar}/helper/sketchybar_metrics"
    if [ -x "$HELPER" ]; then
      read -r MX MY <<< "$("$HELPER" --mouse)"
      read -r RX RY RW RH <<< "$(sketchybar --query ws.$SID | awk '
        /"origin"/ { gsub(/[\[\],]/, ""); x = $2; y = $3 }
        /"size"/   { gsub(/[\[\],]/, ""); w = $2; h = $3 }
        END { if (w != "") printf "%d %d %d %d", x, y, w, h }')"
      if [ -n "$RW" ] && [ "$MX" -ge "$RX" ] && [ "$MX" -lt $((RX + RW)) ] \
         && [ "$MY" -ge "$RY" ] && [ "$MY" -lt $((RY + RH)) ]; then
        exit 0  # мышь всё ещё на пилюле — это переход между зонами
      fi
    fi
    sketchybar --animate tanh 8 --set ws.$SID background.color=0x22ffffff
    ;;

  *)
    if [ "$SID" = "$FOCUSED_WORKSPACE" ]; then
      # Кеш фокуса для быстрых ховер-проверок (пишет только ячейка-фокус,
      # чтобы не делать 9 одинаковых записей на каждое переключение)
      printf '%s' "$FOCUSED_WORKSPACE" > /tmp/sketchybar_focused_ws

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
                 --set ws.$SID background.color=0xffffffff \
                 --set space.$SID label.color=0xff000000 \
                 --set space.$SID.mode label="$LAYOUT_ICON" label.color=0xff000000 \
                 --set space.$SID.fs label="$FS_ICON" label.color=0xff000000
    else
      sketchybar --animate tanh 15 \
                 --set ws.$SID background.color=0x22ffffff \
                 --set space.$SID label.color=0x99ffffff \
                 --set space.$SID.mode label="" \
                 --set space.$SID.fs label=""
    fi
    ;;
esac
