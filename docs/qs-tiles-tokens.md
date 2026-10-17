# Android 17 (LineageOS 24.0) — визуальные токены плиток Quick Settings (Compose)

Исследование только на чтение. Ни один исходный файл не изменялся.

## 0. Соглашения

База путей — `upstream/`. Короткие имена в ссылках:

| Короткое имя | Полный путь (относительно `upstream/`) |
|---|---|
| `Tile.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/panels/ui/compose/infinitegrid/Tile.kt` |
| `CommonTile.kt` | `…/ui/compose/infinitegrid/CommonTile.kt` |
| `InfiniteGridLayout.kt` | `…/ui/compose/infinitegrid/InfiniteGridLayout.kt` |
| `SquishTile.kt` | `…/ui/compose/infinitegrid/SquishTile.kt` |
| `GridLayout.kt`, `TileGrid.kt`, `QuickQuickSettings.kt`, `PaginatedGridLayout.kt`, `BounceableInfo.kt` | `…/ui/compose/` |
| `BounceableTileViewModel.kt`, `QuickQuickSettingsViewModel.kt`, `InfiniteGridViewModel.kt`, `QSColumnsViewModel.kt`, `TileUiState.kt` | `…/ui/viewmodel/` |
| `QSColumnsRepository.kt`, `LargeTileSpanRepository.kt`, `QuickQuickSettingsRowRepository.kt`, `DefaultLargeTilesRepository.kt`, `GridLayoutTypeRepository.kt`, `TileSquishinessRepository.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/panels/data/repository/` |
| `IconTilesInteractor.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/panels/domain/interactor/` |
| `TileRow.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/panels/shared/model/` |
| `PanelsModuleBase.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/panels/dagger/` |
| `QSHost.java` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/` |
| `QSFragmentCompose.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/qs/composefragment/` |
| `QuickSettingsShadeOverlay.kt` | `lineage-frameworks-base/packages/SystemUI/compose/features/src/com/android/systemui/qs/ui/composable/` |
| `SpannedGrids.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/grid/ui/compose/` |
| `Bounceable.kt` | `lineage-frameworks-base/packages/SystemUI/compose/core/src/com/android/compose/animation/` |
| `PlatformTheme.kt`, `AndroidColorScheme.kt` | `lineage-frameworks-base/packages/SystemUI/compose/core/src/com/android/compose/theme/` |
| `TypographyTokens.kt`, `TypeScaleTokens.kt`, `VariableFontTypeScaleEmphasizedTokens.kt`, `TypefaceTokens.kt` | `…/compose/core/src/com/android/compose/theme/typography/` |
| `SurfaceEffectColors.kt` | `lineage-frameworks-base/packages/SystemUI/pods/common/shared/colors/src/api/` |
| `CustomDynamicColors.java`, `DynamicColors.java`, `ColorScheme.java` | `aosp-libs-systemui/monet/src/com/android/systemui/monet/` |
| `colors.xml`, `colors_dynamic.xml` | `lineage-frameworks-base/core/res/res/values/` |
| `config.xml`, `dimens.xml`, `shade_dimens.xml` | `lineage-frameworks-base/packages/SystemUI/res/values/` (и варианты `res/values-*`) |
| `DesktopSizing.kt`, `QsSplitInternetTile.kt` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/flags/` и `…/qs/flags/` |
| `systemui.aconfig` | `lineage-frameworks-base/packages/SystemUI/aconfig/` |

Метка **«предположение»** означает, что значение выведено логикой или взято из внешнего знания (Compose / Material 3), которого нет в дереве исходников. Метка **«не разрешено»** означает, что значение статически не устанавливается.

Ссылки вида `Tile.kt:139` — номер строки в файле из таблицы выше.

---

## 1. Что реально рисуется по умолчанию (сводка)

1. Режим панели по умолчанию — **Paginated** (постраничная сетка). `GridLayoutTypeRepository.kt:27` (`defaultLayoutType = flowOf(PaginatedGridLayoutType)`). `PanelsModuleBase.kt:85-98` выбирает `InfiniteGridLayout` только при `DualShadeFlag` и `config_useInfiniteGridLayoutAsDefault` (`config.xml:1226` = `false`). `InfiniteGridLayout` служит базовым `PaginatableGridLayout` (`PanelsModuleBase.kt:62-64`).
2. Плитки внутри страницы — те же `Tile` / `InfiniteGridLayout.TileGrid`, которые делегирует Paginated (`PaginatedGridLayout.kt:142-149`).
3. QQS (свёрнутая шапка) использует `QuickQuickSettings.kt`: тот же `Tile`, без reveal-эффекта (`QuickQuickSettings.kt:66-85`).
4. Портретный телефон: **4 колонки**, **плитка 72 dp**, **зазор 8 dp**, **боковые поля 16 dp**, **Paginated: 4 строки на страницу**, **QQS: 2 строки**.

---

## 2. Размеры и геометрия плитки

### 2.1 Высота и ширина

| Токен | Значение | Источник |
|---|---|---|
| Высота плитки (`TileHeight`) | **72 dp** | `shade_dimens.xml:39` (`common_tile_default_tile_height`); геттер `CommonTile.kt:477-480`; применение в `TileContainer`: `Tile.kt:394` (`height(TileHeight)`), `Tile.kt:395` (`fillMaxWidth()`) |
| Высота статичных плиток | 72 dp | `Tile.kt:422` (`SmallStaticTile`), `Tile.kt:446` (`LargeStaticTile`) |
| Ширина | Полная ширина ячейки сетки; у large — ширина `largeSpan` ячеек | `Tile.kt:235` (`fillMaxWidth()` в `Tile`) |

Ширину ячеек считает `VerticalSpannedGrid` → `SpannedGrid` через `calculateCellsCrossAxisSize` (равные колонки за вычетом зазоров): `SpannedGrids.kt:216-221`. Детали округления внутри `calculateCellsCrossAxisSize` не открывались (предположение: равные доли с остатком по колонкам).

Вычисленные значения (предположение, по формуле из `SpannedGrids.kt` и полям из 2.6):

| Ширина экрана | Ширина колонки | Ширина large (2 колонки) |
|---|---|---|
| 360 dp (типичный Android) | (360 − 32 − 3·8) / 4 = **76 dp** | 2·76 + 8 = **160 dp** |
| 375 pt (iPhone 8) | (375 − 32 − 3·8) / 4 = **79.75 pt** | 2·79.75 + 8 = **167.5 pt** |

### 2.2 Форма и скругления (active / inactive)

Скругления задаются через `CornerSize`, который анимируется как `Dp` (`Tile.kt:641-654`). Плитка и иконка получают разные `RoundedCornerShape`.

| Состояние | Скругление плитки (`tileRadius`) | Скругление иконки (`iconRadius`) | Источник |
|---|---|---|---|
| ACTIVE | **24 dp** (`common_tile_default_active_tile_corner_radius`) | **16 dp** | `shade_dimens.xml:31-32`; `Tile.kt:613`, `Tile.kt:622`; геттеры `CommonTile.kt:413-421` |
| INACTIVE | **50 dp** (`inactive_tile_corner_radius` → `inactive_icon_corner_radius`) | **50 dp** | `shade_dimens.xml:35-36`; `Tile.kt:614`, `Tile.kt:623`; геттеры `CommonTile.kt:428-436` |
| UNAVAILABLE | как INACTIVE (50 / 50 dp) | как INACTIVE | `Tile.kt:615`, `Tile.kt:624` |

Заметка по геометрии: Compose ограничивает `RoundedCornerShape` половиной меньшей стороны. Для плитки высотой 72 dp радиус 50 dp фактически даёт **полную капсулу** (радиус 36 dp). Для тогл-зоны 56 dp радиус 50 dp даёт круг (радиус 28 dp). Клампинг — предположение о стандартном поведении Compose, в дереве не проверено.

Анимация формы: `animateShapeAsState` → `animateDpAsState` (`Tile.kt:641-643`), метки `QSTileCornerRadius` (`Tile.kt:638`) и `QSTileIconCornerRadius` (`Tile.kt:632`). Спек явно не задан, значит используется дефолтный `spring()` (предположение, см. раздел 5.1).

Фокусная рамка: `borderOnFocus(color = MaterialTheme.colorScheme.secondary, tileShape.topEnd)` (`Tile.kt:230-233`).

### 2.3 Иконка и тогл-зона

| Элемент | Значение | Источник |
|---|---|---|
| Иконка «только иконка» (`SmallTileIconSize`) | **32 dp** | `shade_dimens.xml:34` (`common_tile_default_icon_size`); геттер `CommonTile.kt:508-511`; дефолт параметра `CommonTile.kt:244` |
| Иконка в large-плитке (`LargeTileIconSize`) | **28 dp** | `shade_dimens.xml:37`; геттер `CommonTile.kt:501-506`; применение `CommonTile.kt:176` |
| Тогл-зона (`ToggleTargetSize`) | **56 dp** | `shade_dimens.xml:40`; геттер `CommonTile.kt:482-485`; `CommonTile.kt:145-148` |
| Боковая иконка (`sideDrawable`) | **32 × 20 dp** | `CommonTile.kt:487-488`; `CommonTile.kt:191-197` |
| Шеврон (`ChevronSize`) | 14 dp (определён, в просмотренных плитках не используется) | `CommonTile.kt:489` |

Наблюдения:
- У icon-only плитки **нет отдельной тогл-зоны**: иконка 32 dp стоит по центру всей плитки 72 dp (`Tile.kt:313-319`).
- У large-плитки коробка 56 dp создаётся всегда (`CommonTile.kt:145-148`), но подложка (`drawBehind`) и клип по форме иконки и клик включаются только при `isDualTarget` (`CommonTile.kt:146-158`). Значит, видимая круглая подложка 56 dp есть только у dual-target.

### 2.4 Отступы внутри плитки

| Токен | Значение | Источник |
|---|---|---|
| Начальный отступ large (`StartPadding`) | **8 dp** | `shade_dimens.xml:38`; геттер `CommonTile.kt:472-475`; `CommonTile.kt:377-382` |
| Конечный отступ large (`TileEndPadding`) | **12 dp** (захардкожено) | `CommonTile.kt:490`; `CommonTile.kt:377-382` |
| Конечный отступ large с настройками (`DualTargetEndPadding`) | **8 dp** | `shade_dimens.xml:33`; геттер `CommonTile.kt:423-426`; выбор: `Tile.kt:345-347` (`largeTilePadding(isDualTarget = uiState.handlesSettingsClick)`) |
| Промежуток иконка ↔ текст (`TileArrangementPadding`) | **6 dp** (`Arrangement.spacedBy`) | `CommonTile.kt:491`; `Tile.kt:471-473` (`tileHorizontalArrangement`); применяется `CommonTile.kt:137` |
| Ширина размытия конца текста (`TileLabelBlurWidth`) | **32 dp** | `CommonTile.kt:492`; `CommonTile.kt:343-344`, `:352` |

Внутри large-плитки: ряд `Row` с выравниванием по центру по вертикали (`CommonTile.kt:135-139`), тогл-зона 56 dp (по 8 dp сверху и снизу при высоте 72 dp), подписи в `Modifier.weight(1f)` (`CommonTile.kt:181-189`), затем боковая иконка (`CommonTile.kt:191-197`).

### 2.5 Сетка, колонки, строки, зазоры

| Параметр | Значение (portrait phone, по умолчанию) | Вариации | Источник |
|---|---|---|---|
| Колонки (`quick_settings_infinite_grid_num_columns`) | **4** | land: 8; sw600dp-port: 6 | `config.xml:68`; `values-land/config.xml:30`; `values-sw600dp-port/config.xml:25`; читается в `QSColumnsRepository.kt:44-49` |
| Колонки в split / dual | 4 | split: 6 (sw600dp-long, w1200dp) | `config.xml:74`, `:77`; `values-sw600dp-long/config.xml:24`; `values-w1200dp/config.xml:22` |
| Строки на страницу Paginated (`quick_settings_paginated_grid_num_rows`) | **4** | land: 2; sw600dp-port: 3; sw600dp-land: 3 | `config.xml:62`; `values-land/config.xml:24`; `values-sw600dp-port/config.xml:19`; `values-sw600dp-land/config.xml:28` |
| Строки QQS (`quick_qs_paginated_grid_num_rows`) | **2** | land: 1; sw600dp-port: 2; sw600dp-land: 2 | `config.xml:65`; `values-land/config.xml:27`; `values-sw600dp-port/config.xml:22`; `values-sw600dp-land/config.xml:31` |
| Зазор между колонками (`qs_tile_margin_horizontal`) | **8 dp** | — | `dimens.xml:706`; передаётся `InfiniteGridLayout.kt:105`, `QuickQuickSettings.kt:59` |
| Зазор между строками (`qs_tile_margin_vertical`) | **8 dp** (равен горизонтальному) | — | `dimens.xml:707`; передаётся `InfiniteGridLayout.kt:106`, `QuickQuickSettings.kt:60` |
| Максимальная ширина large (`quick_settings_infinite_grid_tile_max_width`) | **4** (используется только при крупном шрифте) | — | `config.xml:71`; `LargeTileSpanRepository.kt:57` |
| Ширина large по умолчанию (`DEFAULT_LARGE_TILE_WIDTH`) | **2** колонки (половина ряда из 4) | — | `LargeTileSpanRepository.kt:61`, `:51`; `QSColumnsViewModel.kt:64-70` |
| Порог крупного шрифта | `fontScale >= 1.8` | — | `LargeTileSpanRepository.kt:60`, `:53-54` |
| Минимум плиток в настройках (`quick_settings_min_num_tiles`) | **6** | — | `config.xml:106` |

Логика колонок:
- `QSColumnsViewModel.columns` равно `columnsWithoutMedia`, а при media-in-row в landscape делится на 2 (`QSColumnsViewModel.kt:48-54`).
- `largeSpan` равно `defaultTileMaxWidth` (2) без крупного шрифта. При крупном шрифте это `columns / 2` (если `columns > maxSpan`) или `columns` (`QSColumnsViewModel.kt:64-70`).

### 2.6 Боковые поля панели, верх сетки, страницы

| Параметр | Значение | Источник |
|---|---|---|
| Боковое поле QS-колонки (`qs_horizontal_margin`) | **16 dp** (portrait phone); 24 dp (sw600dp-land); 40 dp (sw720dp-land) | `dimens.xml:719` → `dimens.xml:314` (`notification_side_paddings_single` = 16 dp); `values-sw600dp-land/dimens.xml:31`; `values-sw720dp-land/dimens.xml:27`. Применение: `QSFragmentCompose.kt:779` (QQS), `:900-901` (QS) |
| Верхний отступ сетки (`QuickSettingsShade.Dimensions.VerticalPadding`) | **16 dp** | `shade_dimens.xml:56` (`overlay_qs_layout_vertical_padding`); `QuickSettingsShadeOverlay.kt:541-544`; применение `QSFragmentCompose.kt:898-899` |
| Горизонтальный отступ overlay-шейда (`HorizontalPadding`) | 16 dp (для слайдеров и прочих блоков) | `shade_dimens.xml:55`; `QuickSettingsShadeOverlay.kt:536-539`; `QSFragmentCompose.kt:970-976` |
| Доп. верхний отступ QS (`qs_panel_padding_top`) | 80 dp (phone) | `dimens.xml:735`; `QSFragmentCompose.kt:797`, `:845` (ветви не проверялись полностью) |
| Отступ между страницами Paginated (`InterPageSpacing`) | **16 dp** | `PaginatedGridLayout.kt:164`; `:114`, `:136` |
| Высота футера Paginated (`FooterHeight`) | **48 dp** (точки страниц, номер сборки, кнопка редактирования) | `PaginatedGridLayout.kt:163`, `:189`; `FooterBar` `:168-210` |
| Горизонтальный spacing футера | 8 dp | `PaginatedGridLayout.kt:191` |
| Видимых страниц вне viewport | 1 | `PaginatedGridLayout.kt:137` |

Итоговая геометрия страницы Paginated на портретном телефоне (предположение, сборка из перечисленных токенов):
- Сетка страницы: 4 строки × 72 dp + 3 × 8 dp = **312 dp** по высоте, 4 колонки.
- QQS: 2 строки × 72 dp + 1 × 8 dp = **152 dp** по высоте, 4 колонки (`QuickQuickSettingsViewModel.kt:58-64`, `:76-80`).
- На странице до 16 иконок (4×4), при large-плитках меньше.

Примечание: `PaginatedGridLayout.kt:129-135` даёт пейджеру `padding(horizontal = -16 dp)`, а страницам — `contentPadding` 16 dp. Так клип пейджера выходит за поля, а содержимое остаётся на полях 16 dp.

---

## 3. Типографика

| Роль | Токен Material | Шрифт / вес | Размер / lineHeight / tracking | Источник |
|---|---|---|---|---|
| Заголовок плитки (`label`) | `MaterialTheme.typography.titleSmallEmphasized` | variable-font `titleSmallEmphasized`, **SemiBold (600)** | **14 sp / 20 sp / 0 sp** | `CommonTile.kt:217`; `TypographyTokens.kt:213-220` (`fontWeight = FontWeight.SemiBold`); `VariableFontTypeScaleEmphasizedTokens.kt:78-81`; шрифт `TypefaceTokens.kt:52` |
| Вторичная подпись (`secondaryLabel`) | `MaterialTheme.typography.labelMedium` | plain, **Medium (500)** | **12 sp / 16 sp / 0.1 sp** | `CommonTile.kt:225`; `TypographyTokens.kt:106-113`; `TypeScaleTokens.kt:72-76` (вес `WeightMedium`, `TypefaceTokens.kt:30`) |
| Базовый `titleSmall` (справочно) | — | plain, Medium | 14 sp / 20 sp / 0 sp | `TypeScaleTokens.kt:92-96` |

Примечания:
- `TileLabel` ограничивает текст одной строкой (`maxLines = 1`, `CommonTile.kt:329`). Для marquee используется `basicMarquee` с `iterations = TILE_MARQUEE_ITERATIONS = 1` и `initialDelayMillis = TILE_INITIAL_DELAY_MILLIS = 2000` (`CommonTile.kt:323`, `:359-362`, `:493-494`). Если текст шире ячейки, включается затухание края шириной 32 dp (`CommonTile.kt:334-358`).
- Вторичная подпись показывается, только если строка не пустая (`CommonTile.kt:221`). В `LargeStaticTile` подпись пустая (`Tile.kt:452`).

---

## 4. Цвета по состояниям

### 4.1 Роли Material (что использует каждое состояние)

Выбор `TileColors` делает `TileDefaults.getColorForState` (`Tile.kt:588-608`). Поля `TileColors`: `background`, `iconBackground`, `label`, `secondaryLabel`, `icon` (`Tile.kt:512-518`).

| Состояние (`visualState`) | Тип плитки | background | iconBackground | label | secondaryLabel | icon | Источник |
|---|---|---|---|---|---|---|---|
| ACTIVE, single-target (или icon-only dual) | — | `primary` | `primary` | `onPrimary` | `onPrimary` | `onPrimary` | `Tile.kt:529-536` |
| ACTIVE, large dual-target | large + `handlesToggleClick` | `LocalAndroidColorScheme.surfaceEffect1` | `primary` | `onSurface` | `onSurface` | `onPrimary` | `Tile.kt:541-548` |
| INACTIVE, single-target | — | `LocalAndroidColorScheme.surfaceEffect1` | прозрачный | `onSurface` | `onSurface` | `onSurface` | `Tile.kt:563-570` |
| INACTIVE, large dual-target | large + dual | `surfaceEffect1` | `surfaceEffect2` | `onSurface` | `onSurface` | `onSurface` | `Tile.kt:552-559` |
| UNAVAILABLE | любая | `surface.copy(alpha = 0.18)` | то же | `onSurfaceVariant.copy(alpha = 0.38)` | то же | то же | `Tile.kt:574-584` |

Состояние берётся из `TileUiState`: `visualState` = `STATE_UNAVAILABLE`, если `disabledByPolicy`, иначе `state` (`TileUiState.kt:129`). Клик доступен при `state != STATE_UNAVAILABLE` (`TileUiState.kt:134`).

Важно: фон неактивной плитки — **не** `surfaceContainerHighest`. Фон — `LocalAndroidColorScheme.surfaceEffect1` (`Tile.kt:565`). `surfaceContainerHighest` в плитках QS не используется.

Фокусная рамка: `MaterialTheme.colorScheme.secondary` (`Tile.kt:231`, `CommonTile.kt:144`).

Источник `surfaceEffect1/2`: `AndroidColorScheme.kt:82-83` (поля), значения `customColorSurfaceEffect1/2` через `SurfaceEffectColors.kt:31-44`.

### 4.2 Дефолтные значения (статические, без обоев)

Значения из `core/res/res/values/colors.xml`, палитра по умолчанию. Это **не** вычисленные по обоям значения: при динамических обоях `ColorScheme` (`ColorScheme.java`, `DynamicColors.java`) переопределяет их в рантайме.

| Роль | Light | Dark | Источник |
|---|---|---|---|
| `primary` | `#4C5E8B` | `#B8C6EE` | `colors.xml:613` (`system_primary_light`); `colors.xml:746` (`system_primary_dark`) |
| `onPrimary` | `#F9F8FF` | `#323F60` | `colors.xml:581`; `colors.xml:714` |
| `onSurface` | `#30323A` | `#E4E5F0` | `colors.xml:589`; `colors.xml:722` |
| `onSurfaceVariant` | `#5D5F68` | `#A9AAB5` | `colors.xml:591`; `colors.xml:724` |
| `surface` | `#FAF8FE` | `#0D0E12` | `colors.xml:629`; `colors.xml:762` |
| `surfaceEffect1` (фон плитки) | `#FAF8FE` | `#121317` | `colors.xml:858`; `colors.xml:912` |
| `surfaceEffect2` (подложка иконки dual) | `#FFFFFF` | `#D9E2FF` | `colors.xml:860`; `colors.xml:914` |
| `secondary` (рамка фокуса) | `#585F72` | `#C0C6DC` | `colors.xml:621`; `colors.xml:754` |
| `surfaceContainerHighest` (в плитках не используется) | `#E1E2ED` | `#23262E` | `colors.xml:637`; `colors.xml:770` |
| `system_accent1_600` (справочно) | `#4B5D8B` | — | `colors.xml:258` |
| `system_accent1_100` (справочно) | — | `#D9E2FF` | `colors.xml:404` |

Связи: `colors_dynamic.xml:126`, `:134` связывают `materialColorPrimary` и `materialColorSurface` с `system_*`; `colors_dynamic.xml:180-184` связывают `customColorSurfaceEffect*` с `system_surface_effect_*_light`. Тональные правила monet для этих ролей: `CustomDynamicColors.java:344-388`.

Тональные правила monet (`CustomDynamicColors.java`):
- `surfaceEffect1`: neutral-палитра, тон **98** (light) / **6** (dark), `opacity = 0.54` (`CustomDynamicColors.java:354-361`).
- `surfaceEffect2`: primary-палитра, тон **100** (light) / **90** (dark), `opacity = 0.32` (light) / **0.15** (dark) (`CustomDynamicColors.java:364-371`).
- `surfaceEffect0`: primary, тон 90 / 20, `opacity 0.5` (`CustomDynamicColors.java:344-351`). В плитках QS не используется.

Не разрешено статически: как именно применяется `opacity` monet (0.54 / 0.32 / 0.15). В статических `colors.xml` альфы нет. Предположение: альфа учитывается при генерации ресурсов в рантайме.

Hex-значения для произвольного seed из обоев **не разрешены** без запуска ColorScheme.

Тональные роли Material 3 (`MaterialDynamicColors`: `primary`, `onPrimary`, `onSurface` и др.) в дереве не найдены: класс приходит из внешней библиотеки material-color-utilities. Тоны light/dark для `primary` (T40/T80), `onPrimary` (T100/T20), `onSurface` (T10/T90) — предположение по спецификации M3.

### 4.3 Альфа для UNAVAILABLE

Жёстко заданы в коде, не токены: `surface.copy(alpha = 0.18f)` и `onSurfaceVariant.copy(alpha = 0.38f)` (`Tile.kt:575-576`).

---

## 5. Состояния: форма, иконка, фон и переходы

### 5.1 Что анимируется при смене состояния

| Анимация | Спек | Метка | Источник |
|---|---|---|---|
| Цвет фона плитки | `animateColorAsState` (дефолтный) | `QSTileBackgroundColor` | `Tile.kt:180` |
| Цвет подписи | `animateColorAsState` (дефолтный) | `QSTileLabelColor` | `CommonTile.kt:211` |
| Цвет вторичной подписи | `animateColorAsState` (дефолтный) | `QSTileSecondaryLabelColor` | `CommonTile.kt:212-213` |
| Цвет иконки | `animateColorAsState` (дефолтный) | `QSTileIconColor` | `CommonTile.kt:249` |
| Цвет подложки иконки (dual) | `animateColorAsState` (дефолтный) | `QSTileDualTargetBackgroundColor` | `CommonTile.kt:142-143` |
| Радиус плитки | `animateDpAsState` (дефолтный) | `QSTileCornerRadius` | `Tile.kt:190`, `Tile.kt:637-643` |
| Радиус иконки | `animateDpAsState` (дефолтный) | `QSTileIconCornerRadius` | `Tile.kt:629-634`, `Tile.kt:643` |

Длительности и кривые в исходниках не заданы. Значит, используется дефолтный `spring()` из `androidx.compose.animation.core`. Предположение (внешнее знание Compose, не из дерева): `dampingRatio = 1.0` (без отскока) и `stiffness = 1500` (`StiffnessMedium`), визуально порядка 250–350 мс. Точные значения в дереве не найдены.

### 5.2 Анимированная иконка (AVD)

Иконки AnimatedVectorDrawable при первом появлении не проигрываются: `shouldSkipInitialAnimation` (`CommonTile.kt:264-268`). При смене иконки `atEnd` переключается (`CommonTile.kt:274-278`). Тайминг AVD берётся из ресурсов, в коде не задан.

### 5.3 Reveal-эффект (только при `enableRevealEffect = true`)

`Tile.kt:186-211`: `verticalTactileSurfaceReveal` с `deltaY = QuickSettingsShade.Dimensions.VerticalPadding` (16 dp), `phase1MarginX = InactiveIconCornerRadius` (50 dp), `maxCornerSize = animatedCornerRadius` (`Tile.kt:194-203`). Для контента — `verticalFadeContentReveal` с тем же `deltaY` (`Tile.kt:206-207`). Параметры spec находятся в библиотеке `mechanics` и не просмотрены.

В Paginated `enableRevealEffect = false` (`PaginatedGridLayout.kt:147`). В QQS параметр не передаётся, дефолт `false` (`Tile.kt:150`; `QuickQuickSettings.kt:66-85`).

---

## 6. Нажатие: bounce, длительности, кривые

### 6.1 Контейнер (`BounceableImpl`)

- Амплитуда контейнера: **8 dp** (`BounceableTileViewModel.kt:72`, `BounceSize = 8.dp`). Создаётся как `BounceableImpl(BounceSize)` (`BounceableTileViewModel.kt:28`).
- Спек: `spring()` по умолчанию (`Bounceable.kt:70`).
- При нажатии: `animateExpansion` → цель `bounceSize` (`Bounceable.kt:77-79`). Контейнер растёт по горизонтали; соседние плитки в той же строке ужимаются (`Tile.kt:236-243`, `BounceableInfo.kt:33-53`).
- При отпускании: `animateToRest` ждёт, пока значение превысит `0.75 × bounceSize` (`MINIMUM_BOUNCE_RATIO = .75f`, `Bounceable.kt:100`), не дольше 1000 мс (`MAX_WAIT_TIME_MILLIS`, `Bounceable.kt:101`, `:86-95`), затем анимирует в 0 (`Bounceable.kt:81-84`).
- Ориентация: `Orientation.Horizontal` (`Tile.kt:240`).
- Последний столбец: `bounceEnd = !onLastColumn` (`BounceableInfo.kt:48`, `:51-53`; `Tile.kt:241`).

### 6.2 Содержимое (иконка / текст), `keyframes`

- Масштаб иконки: **1.10** (`BounceableTileViewModel.kt:75`). Масштаб текста: **1.06** (`:76`).
- Длительность цикла: **334 мс** = `167 × 2` (`BounceableTileViewModel.kt:78`).
- Ключевые кадры (`BounceableTileViewModel.kt:63-66`): пик в 167 мс с `BounceStartEasing = CubicBezier(.05, 0, 0, 1)` (`:73`); возврат к 1.0 в 334 мс с `BounceEndEasing = CubicBezier(1, 0, .95, 1)` (`:74`).
- Выбор: если контейнер не bounce'ит, вызывается `animateContentBounce(iconOnly)` (`Tile.kt:293-299`; `BounceableTileViewModel.kt:39-45`).
- Иконка icon-only плитки масштабируется по `iconBounceScale` с центром опоры (`Tile.kt:316-319`; `CommonTile.kt:393-405`, дефолт `TransformOrigin.Center`).
- Текст large-плитки: `bounceScale(TransformOrigin(0f, .5f), textScale)` (`CommonTile.kt:188`), то есть опора у левого края. Масштаб берётся из `Tile.kt:343`.

Когда bounce идёт по контейнеру: `bounceContainer = uiState.isToggleable && (iconOnly || !isDualTarget)` (`Tile.kt:269`). Значит:
- toggle-плитки (single и icon-only dual): bounce контейнера;
- large dual-target: bounce текста (`Tile.kt:297`, `Tile.kt:343`);
- нетогглевые icon-плитки: bounce иконки.

### 6.3 Сжатие по вертикали (squish)

- Дефолт `squishiness = 1f` (`TileSquishinessRepository.kt:39`). Значение задаётся извне (`TileSquishinessRepository.kt:30-36`).
- `Modifier.verticalSquish`: высота = `lookaheadSize.height × squishiness`, содержимое центрируется (`SquishTile.kt:35-57`). Применяется в `TileExpandable` (`Tile.kt:372-373`) и к тогл-зоне large (`CommonTile.kt:152`).
- Squish влияет только на высоту; ширина не меняется.

---

## 7. Сетка и наполнение (QQS и Paginated)

### 7.1 Сколько плиток видно

- QQS: `QuickQuickSettingsViewModel.kt:58-64` задаёт `rows = quick_qs_paginated_grid_num_rows`, при media-in-row в landscape умножает на 2. Плитки: `splitInRowsSequence(tiles, columns).take(rows)` (`QuickQuickSettingsViewModel.kt:76-80`).
- Paginated: страницы — `chunked(rows)` из рядов по `columns` (`InfiniteGridViewModel.kt:60-67`). Без large-плиток — 16 на страницу.

### 7.2 Иконка или large

- Плитка — иконка, если ширина `1` (`TileRow.kt:23-24`, `isIcon`).
- Ширина = `largeSpan`, если плитка в `largeTiles` (`InfiniteGridViewModel.kt:69-73`; `QuickQuickSettingsViewModel.kt:94`).
- В гриде `iconOnly = !largeTiles.contains(spec)` (`IconTilesInteractor.kt:54`).

### 7.3 Дефолтный набор плиток

Нерасширенный (по умолчанию, `QsSplitInternetTile` выключен):
- Порядок (`config.xml:82-85`): `internet, bt, dnd, cast, flashlight, airplane, rotation, wallet, alarm, controls, screenrecord, battery` (12 шт.).
- Крупные по умолчанию: `internet, bt, dnd, cast`, захардкожено (`DefaultLargeTilesRepository.kt:44-49`).

Split (при включённом `qs_split_internet_tile_rw`):
- Порядок (`config.xml:87-89`): `wifi, bt, cell, cast, dnd, wallet, airplane, rotation, flashlight, battery, alarm, controls, screenrecord` (13 шт.).
- Крупные (`config.xml:92-98`): `wifi, bt, cell, cast, dnd, wallet`.

Выбор строки: `QSHost.java:45-46`. Выбор крупных: `DefaultLargeTilesRepository.kt:38-42`.

`QsSplitInternetTile.isEnabled = qsSplitInternetTileRw() && !qsSplitInternetTileSuppression()` (`QsSplitInternetTile.kt`). В `systemui.aconfig:1380-1384` значение по умолчанию не указано. Предположение: флаг выключен.

Lineage-override: в sparse-клоне нет `res-lineage` и нет переопределения `quick_settings_tiles_default` или `quick_settings_large_tiles_default_split`. Найден только AOSP-набор в `SUI/res/values/config.xml`. Предположение: дефолты Lineage 24.0 совпадают с этими, полного дерева ресурсов Lineage здесь нет.

Список всех нативных плиток (справочно): `config.xml:94` (`quick_settings_tiles_stock`).

### 7.4 Крупный шрифт

При `fontScale >= 1.8` (`LargeTileSpanRepository.kt:60`) `largeSpan = columns / 2`, если `columns > 4`, иначе `columns` (`QSColumnsViewModel.kt:64-70`). Без порога `largeSpan = 2`.

---

## 8. Сводная таблица токенов

| Категория | Токен | Значение | Источник |
|---|---|---|---|
| Геометрия | Высота плитки | 72 dp | `shade_dimens.xml:39`; `CommonTile.kt:477-480` |
| Геометрия | Ширина колонки | (W − 32 − 3·8) / 4 (предположение) | `SpannedGrids.kt:216-221` |
| Геометрия | Зазор колонок / строк | 8 dp / 8 dp | `dimens.xml:706-707` |
| Геометрия | Колонки (phone portrait) | 4 | `config.xml:68` |
| Геометрия | Строки на страницу (Paginated) | 4 | `config.xml:62` |
| Геометрия | Строки QQS | 2 | `config.xml:65` |
| Геометрия | Large span по умолчанию | 2 колонки | `LargeTileSpanRepository.kt:61` |
| Геометрия | Боковое поле | 16 dp | `dimens.xml:719`, `dimens.xml:314` |
| Геометрия | Верхнее поле сетки | 16 dp | `shade_dimens.xml:56`; `QSFragmentCompose.kt:898` |
| Геометрия | Межстраничный отступ | 16 dp | `PaginatedGridLayout.kt:164` |
| Геометрия | Высота футера Paginated | 48 dp | `PaginatedGridLayout.kt:163` |
| Скругление | Active плитка / иконка | 24 dp / 16 dp | `shade_dimens.xml:31-32` |
| Скругление | Inactive плитка / иконка | 50 dp / 50 dp (капсула / круг) | `shade_dimens.xml:35-36` |
| Иконка | Small / Large | 32 dp / 28 dp | `shade_dimens.xml:34`, `:37` |
| Иконка | Тогл-зона | 56 dp | `shade_dimens.xml:40`; `CommonTile.kt:145-148` |
| Иконка | Боковая иконка | 32 × 20 dp | `CommonTile.kt:487-488` |
| Отступы | Старт large / конец large / конец с настройками | 8 / 12 / 8 dp | `shade_dimens.xml:38`, `:33`; `CommonTile.kt:490`; `Tile.kt:345-347` |
| Отступы | Иконка ↔ текст | 6 dp | `CommonTile.kt:491` |
| Текст | Заголовок | 14 sp / 20 sp, SemiBold | `TypographyTokens.kt:213-220`; `VariableFontTypeScaleEmphasizedTokens.kt:78-81` |
| Текст | Подпись | 12 sp / 16 sp, Medium, tracking 0.1 | `TypographyTokens.kt:106-113`; `TypeScaleTokens.kt:72-76` |
| Текст | Marquee | 1 повтор, задержка 2000 мс | `CommonTile.kt:493-494` |
| Текст | Затухание края | 32 dp | `CommonTile.kt:492` |
| Цвет | Active фон / иконка / подпись | primary / onPrimary / onPrimary | `Tile.kt:529-536` |
| Цвет | Inactive фон / иконка / подпись | surfaceEffect1 / onSurface / onSurface | `Tile.kt:563-570` |
| Цвет | Unavailable | surface·0.18 / onSurfaceVariant·0.38 | `Tile.kt:574-584` |
| Цвет | Фокусная рамка | secondary | `Tile.kt:231` |
| Анимация | Bounce контейнера | 8 dp, spring() | `BounceableTileViewModel.kt:72`; `Bounceable.kt:70` |
| Анимация | Bounce иконки | ×1.10, 334 мс | `BounceableTileViewModel.kt:75`, `:78` |
| Анимация | Bounce текста | ×1.06, 334 мс | `BounceableTileViewModel.kt:76`, `:78` |
| Анимация | Кривые вверх / вниз | CB(.05,0,0,1) / CB(1,0,.95,1) | `BounceableTileViewModel.kt:73-74` |
| Анимация | Цвета / радиусы | animateColorAsState / animateDpAsState, спек не задан | `Tile.kt:180`, `Tile.kt:643` |
| Анимация | Squish | 1 по умолчанию | `TileSquishinessRepository.kt:39` |

---

## 9. Не разрешено и предположения (сводно)

1. **Hex для произвольного seed из обоев** не разрешён: ColorScheme и monet генерируют его в рантайме. Статические дефолты (раздел 4.2) взяты из `colors.xml`.
2. **Альфа-эффект `opacity` monet** (0.54 / 0.32 / 0.15, `CustomDynamicColors.java:354-371`) не виден в статических `colors.xml`. Как он применяется в ресурсах, не проверено.
3. **Тоны M3** (`primary` T40/T80, `onSurface` T10/T90 и т.п.) не найдены в дереве (`MaterialDynamicColors` внешний). Значения — предположение по спецификации M3.
4. **Спек анимаций цвета и формы** (`animateColorAsState`, `animateDpAsState`, `spring()` по умолчанию): длительности в коде не заданы. Предположение: `dampingRatio = 1`, `stiffness = 1500`.
5. **Формула округления ширины ячеек** (`calculateCellsCrossAxisSize`) открыта не полностью. Предположение: равные доли с остатком.
6. **Капсула 50 dp при высоте 72 dp** — клампинг Compose, предположение о стандартном поведении.
7. **Флаги.** `desktop_sizing` меняет размеры на планшетах (плитка 56 dp, иконка 20 dp, скругления 22/28 dp, `sw600dp/shade_dimens.xml:21-56`). `DesktopSizing.isEnabled = Flags.desktopSizing() && SceneContainerFlag.isEnabled` (`DesktopSizing.kt`). Значения по умолчанию в aconfig не указаны. Предположение: оба флага выключены, поэтому базовые значения применяются.
8. **Lineage-override** не найден в sparse-клоне. Значения — AOSP-дефолты из `SUI/res/values/`.
9. **Reveal-spec** (`VerticalTactileSurfaceRevealEffect`, `verticalFadeContentReveal`) — библиотека `mechanics`, не просмотрена.
10. **`qs_tile_text_size` (14 sp, `dimens.xml:733`)** определён; использование в compose-плитках не проверялось.

Не исследовано: `EditTile.kt` и режим редактирования (вне задачи), `QSFragmentCompose.kt` целиком (только отступы), `TileDetails.kt`, `Tooltip.kt`, строки состояний `QSTile`.

## Дополнение (проверено по platform/build/release android-17.0.0_r1)
- `qs_split_internet_tile_rw` ENABLED только в `cp2a` (следующий релиз). В `cp1a` (Android 17.0) его нет. Для 17.0 берём **несплитный** набор: `internet,bt,dnd,cast,flashlight,airplane,rotation,wallet,alarm,controls,screenrecord,battery`, крупные — `internet,bt,dnd,cast`. Предположение: Lineage 24.0 собирается с `cp1a`.
- В `cp2a` также `qs_power_icon_refresh` ENABLED.
- В `quick_settings_tiles_stock` (config.xml:109) есть плитки Lineage: `ambient_display, aod, caffeine, heads_up, powershare, profiles, reading_mode, sync, usb_tether, vpn`.
