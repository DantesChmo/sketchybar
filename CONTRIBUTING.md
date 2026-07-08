# Contributing

Гайд по устройству этого конфига SketchyBar и по тому, как его дорабатывать.

## Структура

```
sketchybarrc              # точка входа: бар, стили, items, запуск провайдера
plugins/
  aerospace.sh            # индикатор воркспейсов AeroSpace (event-driven)
helper/
  provider.c             # метрики (clock/cpu/ram/battery/calendar) + чтение раскладки (--lang)
  mach.{c,h}             # mach-протокол из исходников SketchyBar
  Makefile               # сборка бинарника sketchybar_metrics
```

Конфиг разложен по `~/.config/sketchybar` (симлинк на этот репозиторий).

## Метрики: единый провайдер, а не скрипты

**Важно:** метрики (часы, CPU, RAM, батарея, календарь) обновляются **не**
per-item скриптами с `update_freq`, а одним долгоживущим процессом
`helper/sketchybar_metrics`.

### Почему так

Модель `update_freq=N script=plugin.sh` каждый тик делает `fork`+`exec` скрипта,
а тот форкает ещё утилиты. Например часы (`update_freq=1`) порождали 3 процесса
в секунду (`bash` → `date` → `sketchybar`), а CPU-плагин запускал `top`, который
на ~250 мс грузил ядро на 100% каждые 30 секунд.

Провайдер держит mach-порт к бару и обновляет items напрямую, без единого
`fork`/`exec`:

| | Форк-модель | Провайдер |
|---|---|---|
| CPU всех метрик | ~13 мс/сек | ~0.33 мс/сек |
| Форков в секунду | 3+ | 0 |
| Источник CPU% | `top` (spike 250 мс) | `host_processor_info` (дельта тиков) |

Метрики берутся из ядра напрямую: CPU — `host_processor_info`, RAM —
`host_statistics64`, батарея — IOKit, время — `strftime`.

### Сборка

```sh
cd ~/.config/sketchybar/helper && make
```

Бинарник `sketchybar_metrics` собирается локально и **не** коммитится (см.
`.gitignore`). Пересобирать нужно только после обновления macOS или смены
архитектуры CPU. `sketchybarrc` запускает провайдер сам и печатает подсказку,
если бинарник не собран.

### Жизненный цикл

`sketchybarrc` при старте/reload делает `pkill` прежнего экземпляра и запускает
новый в фоне (`disown`). Провайдер сам завершится, если бар пропал (не может
найти mach-порт несколько тиков подряд) — оставшихся сирот не будет.

### Как добавить/изменить метрику

1. В `provider.c` добавь функцию-сборщик (по образцу `cpu_usage` / `ram_usage`).
2. В цикле `main()` выбери интервал через `tick % N == 0` и собери команду
   `--set <item> ...`, отправив её через `bar(argc, argv)`.
3. Item создаётся в `sketchybarrc` **без** `script`/`update_freq` — только
   стили и стартовая иконка.
4. Пересобери (`make`) и `sketchybar --reload`.

Интервалы задаются тиками секундного цикла: сейчас clock 1 с, cpu 2 с, ram 5 с,
battery 10 с, calendar 60 с.

## Раскладка клавиатуры — событийно, а не опросом

Язык ввода (`language`) устроен принципиально иначе, чем метрики, и **не** живёт
в цикле провайдера. Причина: macOS **не доставляет** distributed-уведомления о
смене раскладки фоновым процессам, а долгоживущий процесс к тому же навсегда
застревает на значении, которое `TISCopyCurrentKeyboardInputSource` вернул при
старте. Опрос в таком процессе не работает в принципе.

Рабочая схема (в `sketchybarrc`):

```sh
# бар (GUI-процесс) сам ловит системное уведомление и делает из него событие
sketchybar --add event language_change AppleSelectedInputSourcesChangedNotification

sketchybar --add item language right \
    --subscribe language language_change \
    --set language ... script="$HELPER --lang"
```

- Событие ловит **сам sketchybar** — как GUI-процесс он distributed-уведомления
  получает (в отличие от фонового провайдера).
- По событию бар запускает `sketchybar_metrics --lang` — **короткоживущий**
  процесс. При каждом запуске он заново спрашивает у системы текущий язык
  (свежее значение) и ставит label. Стартовое значение проставляется на
  `sketchybar --update` при запуске конфига.
- Форк происходит **только в момент реального переключения языка** (~0 мс CPU,
  процессы не накапливаются), а не по таймеру.

Тот же бинарник в обычном режиме (без `--lang`) работает провайдером метрик —
режим выбирается по аргументу в `main()`.

## Nerd Font иконки — только байтами

Глифы Nerd Font лежат в Private Use Area Unicode. **Не вставляй их символом
напрямую** в исходники — многие редакторы/инструменты молча их проглатывают,
и в файле остаётся пустая строка.

- В C (`provider.c`) — UTF-8 escape'ами: `"\xf3\xb0\x82\x84"` (= `󰂄`).
- В shell (`sketchybarrc`, `plugins/*.sh`) — через `printf`:
  `icon="$(printf '\xef\x82\xb2')"`.

## Плагин AeroSpace (`plugins/aerospace.sh`)

Event-driven, не таймерный: реагирует на событие `aerospace_workspace_change`,
которое шлёт AeroSpace (`~/.config/aerospace/aerospace.toml`). Показывает на
активном воркспейсе раскладку (h_tiles/v_tiles/accordion) и маркер fullscreen.
Индикатор режима resize управляется прямо из биндингов AeroSpace
(`--set aerospace_mode drawing=on/off`), т.к. у AeroSpace нет CLI для запроса
текущего binding-mode.

## Применение изменений

```sh
sketchybar --reload          # перечитать конфиг (перезапустит провайдер)
cd helper && make            # если менялся provider.c
```
