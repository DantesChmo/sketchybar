# SketchyBar config

Конфиг строки состояния [SketchyBar](https://github.com/FelixKratz/SketchyBar)
для macOS с интеграцией тайлингового менеджера
[AeroSpace](https://github.com/nikitabobko/AeroSpace).

**Что показывает:**

- воркспейсы AeroSpace с индикатором раскладки (h_tiles / v_tiles / accordion)
  и маркером fullscreen на активном;
- индикатор режима resize;
- часы, дату, CPU, RAM, батарею;
- текущий язык ввода (EN/RU/…), обновляется мгновенно при смене раскладки.

Все метрики обновляет **один нативный процесс** через mach-порт, без форков и
без запуска `top`/`date` каждую секунду. Язык ввода — событийно: сам бар ловит
системное уведомление о смене раскладки. Подробности в
[CONTRIBUTING.md](CONTRIBUTING.md).

## Требования

| Зависимость | Зачем |
|---|---|
| `sketchybar` | сама строка состояния |
| `aerospace` | тайлинг + события воркспейсов |
| `borders` | подсветка рамки активного окна |
| Hack Nerd Font | иконки в баре |
| Xcode Command Line Tools | `clang` + `make` для сборки провайдера метрик |

> Провайдер метрик — небольшая C-программа, которую нужно **собрать локально**
> (`make`). Поэтому «просто `brew install sketchybar` + `brew services start`»
> уже недостаточно — см. шаг 3.

## Установка

### 1. Зависимости

```sh
# формулы
brew tap FelixKratz/formulae
brew install sketchybar borders

# AeroSpace и шрифт
brew install --cask nikitabobko/tap/aerospace
brew install --cask font-hack-nerd-font

# компилятор (если ещё не стоит Xcode / CLT)
xcode-select --install
```

### 2. Конфиг

SketchyBar читает `~/.config/sketchybar`. Клонируй репозиторий прямо туда:

```sh
git clone <URL-этого-репозитория> ~/.config/sketchybar
```

Либо держи репозиторий где удобно и сделай симлинк:

```sh
git clone <URL> ~/projects/sketchybar
ln -s ~/projects/sketchybar ~/.config/sketchybar
```

### 3. Сборка провайдера метрик

```sh
cd ~/.config/sketchybar/helper && make
```

Появится бинарник `sketchybar_metrics` (в git не коммитится). Пересобирать нужно
только после обновления macOS или смены архитектуры CPU. Если забыть этот шаг —
бар запустится, но метрики (часы/CPU/RAM/батарея/дата) не будут обновляться;
`sketchybarrc` в этом случае напечатает подсказку в лог.

### 4. Запуск сервисов

```sh
brew services start sketchybar
brew services start borders
```

AeroSpace запусти из приложения (или включи автозапуск — в его конфиге уже
стоит `start-at-login = true`).

### 5. Интеграция AeroSpace ↔ SketchyBar

Индикаторы воркспейсов и режимов обновляются по событиям от AeroSpace, поэтому
в `~/.config/aerospace/aerospace.toml` должны быть настроены:

- **событие смены воркспейса** — иначе бар не узнает о переключении:

  ```toml
  exec-on-workspace-change = [
    '/bin/bash', '-c',
    'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE'
  ]
  ```

- **триггеры смены раскладки/режима** — чтобы иконка раскладки, fullscreen и
  плашка `RESIZE` обновлялись мгновенно. К биндингам layout/fullscreen добавлен
  `sketchybar --trigger …`, а вход/выход resize шлёт
  `sketchybar --set aerospace_mode drawing=on/off`.

> `aerospace.toml` живёт в `~/.config/aerospace/` и не входит в этот репозиторий.

## Применение изменений

```sh
sketchybar --reload            # перечитать конфиг (перезапустит провайдер)
cd ~/.config/sketchybar/helper && make   # если менялся provider.c
```

## Разработка

Устройство провайдера, добавление новых метрик и работа с Nerd Font иконками —
в [CONTRIBUTING.md](CONTRIBUTING.md).
