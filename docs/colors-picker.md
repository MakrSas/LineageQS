# Android 17 «Colors» (системные цвета) в ThemePicker: спецификация для UIKit-порта

Источник: `upstream/aosp-ThemePicker/` (platform/packages/apps/ThemePicker, android-17.0.0_r1, sparse).

Соглашения:
- Пути в `src/...` указаны относительно корня `aosp-ThemePicker/`. Короткая запись `picker/color/...` означает `src/com/android/customization/picker/color/...`, `model/color/...` означает `src/com/android/customization/model/color/...`.
- `res/...` указаны относительно корня `aosp-ThemePicker/`.
- «предположение» — вывод, которого нет в коде напрямую (дефолт библиотеки, визуальная интерпретация, значение не задано в доступных файлах).
- Значения из `dp` переносятся 1:1 в pt (Android dp = pt в iOS при @1x-логике), но это тоже предположение для порта.

---

## 0. Что есть и чего нет в этом срезе

Есть в срезе: `picker/color/**` (Compose UI, ViewModel, repository, interactor), `model/color/**` (ColorOption, ColorProvider, ColorProviderUtil), `res/values/{strings,dimens}.xml`, `res/values-ru/strings.xml`.

Отсутствует (ссылки есть, файлов нет):
- `com.android.wallpaper.picker.customization.ui.viewmodel.ColorUpdateViewModel` и константа `COLOR_ANIMATION_DURATION_MILLIS` (`picker/color/ui/compose/ColorPreviewTheme.kt:23,134`). Значение длительности цветовой анимации в срезе не определено.
- `DarkModeViewModel` (`picker/mode/ui/viewmodel/`, импорт в `picker/color/ui/compose/ColorFloatingSheet.kt:79`). Логика переключения тёмной темы не видна.
- `com.android.compose.animation.bounceable` и `OptionBounceable` / `clickBounceAnimate()` (`ColorVariantPicker.kt:51,55,154-167`; `ColorFloatingSheet.kt:72,387`). Параметры пружины/масштаба bounce не определены.
- `com.android.systemui.monet.ColorScheme` (`ColorProviderUtil.kt:29`, `ColorProvider.kt:153`), `com.google.ux.material.libmonet.dynamiccolor.MaterialDynamicColors` / `DynamicScheme` (`ColorPreviewTheme.kt:35-36`, `ColorVariantPicker.kt:56`). Тоновые шкалы `accent1.s200`, `getAtTone(450f)` и т.п. не вычисляются в срезе.
- `CustomizationPreferences`, `ResourceConstants`, `BaseFlags`, `CustomizationManager` (остальные импорты).
- Drawable-ресурсы: `ic_palette_filled_24px`, `edit_icon_foreground` (`ColorFloatingSheet.kt:262,456`), `ic_colors` (`ColorPickerViewModel.kt:265`), `com.android.wallpaper.R.drawable.ic_close`, `ic_check_wallpaper`, `ic_baseline_wallpaper_24` (`DrillDownFloatingSheet.kt:103,123`; `ColorPickerViewModel.kt:264`). Папки `res/drawable` в срезе нет.
- XML-layout `R.layout.color_option` (`model/color/ColorOptionImpl.kt:68`) и XML-вью колорпикера (`ColorsFloatingSheetBinder.kt` ссылается на `R.id.color_type_tab_subhead`).
- `res/values/dimens.xml` включает только часть размеров (см. §6), `res/values/colors.xml` отсутствует, значит все цвета — ролевые токены Material 3, а не константы.
- Превью-карточка телефона (lock screen / shade preview) из скриншота в этом срезе не найдена. Ни одного файла, который её рисует, нет.

Поэтому числовые значения тонов палитры, длительности анимации цвета и параметры bounce в этом документе не подтверждены кодом.

---

## 1. Варианты (variants / ThemeStyle) и источники цветов

### 1.1 Соответствие Neutral / Soft / Bright / Bold

Порядок вариантов при включённом флаге `isColorPickerUpdateEnabled` (это путь, на котором работает `ColorPickerRepositoryImpl` через `ColorOptionImpl.buildSimplifiedSeedOption`):

| Позиция | ThemeStyle | Строка (EN) | Строка (RU) | Источник |
|---|---|---|---|---|
| 1 | `SPRITZ` | Neutral | Нейтральная | `ColorVariantPicker.kt:220-221`, `res/values/strings.xml:651`, `res/values-ru/strings.xml:178` |
| 2 | `TONAL_SPOT` | Soft | Мягкая | `ColorVariantPicker.kt:222-223`, `strings.xml:657`, ru:179 |
| 3 | `VIBRANT` | Bright | Яркая | `ColorVariantPicker.kt:224-225`, `strings.xml:663`, ru:180 |
| 4 | `EXPRESSIVE` | Bold | Насыщенная | `ColorVariantPicker.kt:226-227`, `strings.xml:669`, ru:181 |

Список стилей: `model/color/ColorProviderUtil.kt:313-330`. При флаге ON: `SPRITZ, TONAL_SPOT, VIBRANT, EXPRESSIVE`. При флаге OFF порядок другой: `TONAL_SPOT, SPRITZ, VIBRANT, EXPRESSIVE`. Гипотеза пользователя (Neutral/Soft/Bright/Bold = SPRITZ/TONAL_SPOT/VIBRANT/EXPRESSIVE) подтверждается для флага ON.

Список передаётся в UI как `ColorPickerRepositoryImpl.styleList = colorProvider.styleList` (`picker/color/data/repository/ColorPickerRepositoryImpl.kt:269`), далее в `ColorPickerViewModel.styleOptions` (`picker/color/ui/viewmodel/ColorPickerViewModel.kt:149`).

Content description (для a11y) по стилю: `ColorProviderUtil.kt:111-122` → `content_description_*_color_option` (`res/values/strings.xml:621-645`, «Primary dynamic theme», «Primary neutral theme», «Primary vibrant theme», «Primary expressive theme»).

Важно: по умолчанию в UI вариант для выбранного цвета — стиль, который хранится в системе (`selectedStyle`, `ColorPickerRepositoryImpl.kt:329-336`; фолбэк `TONAL_SPOT`, строки 275-281 и 334).

### 1.2 Сиды для обоев и для freeform

**Обои (wallpaper colors)**

- Берутся из `ColorScheme.getSeedColors(wallpaperColors)` и обрезаются до `MAX_SEED_COLORS = 4` (`model/color/ColorProvider.kt:180-181`, константа `ColorProvider.kt:312`).
- Путь с флагом update (сейчас основной, через `ColorPickerRepositoryImpl` при `shouldUseThemeService`): каждое seed → одна опция `ColorOptionImpl.buildSimplifiedSeedOption(title="", source=HOME, seedColor, defaultStyle=TONAL_SPOT)` (`ColorProvider.kt:183-190`). То есть на каждый seed ровно один вариант `TONAL_SPOT`; остальные варианты выбираются в variant-picker.
- Путь без `isUsingThemeService` (`ColorProvider.kt:191-203`) строит `buildBundle(... style=TONAL_SPOT, isDefault = (i==0))`.
- Легаси-путь с флагом OFF (`ColorProvider.kt:149-173`): цикл seed × `styleList` → до 4 × 4 = 16 опций, плюс монохром (`insertMonochrome`, `ColorProvider.kt:287-308`).
- Точное число вариантов на экране: от 0 до 4 (зависит от `ColorScheme.getSeedColors`; алгоритм выбора seed в срезе отсутствует, предположение: ≤4 всегда, так как `take(4)`).
- Первый seed помечается `isDefault = true` (`ColorProvider.kt:165,199`), и в `getContentDescription` для default выводится `default_theme_title` (`model/color/ColorOption.java:218-229`).

**Пресеты (preset colors)**

- Из stub-APK `COLOR_BUNDLES_ARRAY_NAME`, каждый бандл → `buildSimplifiedSeedOption(title, source=PRESET, seedColor=color, defaultStyle=style)` (`ColorProvider.kt:250-257`). Стиль берётся из `COLOR_BUNDLE_STYLE_PREFIX`, по умолчанию `TONAL_SPOT` (`ColorProvider.kt:228-244`).
- В список добавляются после обоев: `buildFinalList() = wallpaper + preset` (`ColorProvider.kt:284`). Tab «Other colors» / «Другие цвета» (`ColorPickerViewModel.kt:250-257`).

**Freeform (один seed)**

- Один seed на основе hue: `hueToColorOption(hue)` (`model/color/ColorProviderUtil.kt:332-341`):
  - `Hct.from(hue, chroma = 100.0, tone = 80.0)` → `hct.toInt()` → `seedColor`;
  - `defaultStyle = TONAL_SPOT`, `source = COLOR_SOURCE_PRESET`, `title = ""` (TODO b/441279631).
- Freeform-опция вставляется первой в списке: `ColorPickerRepositoryImpl.kt:202-210` (`add(index = 0, FREEFORM_COLOR to listOf(hueToColorOption(hue)))`), только если включён `isColorPickerComposeEnabled()`.
- Hue хранится через `wallpaperPreferences.setFreeformColorHue(hue)` (`ColorPickerRepositoryImpl.kt:408-411`).

**Один seed на основе hue — следствие**: в freeform-экране один seed, один стиль (`TONAL_SPOT` по умолчанию), варианты выбираются тем же drill-down, что и для обоев.

### 1.3 Как выбирается и отображается «выбранная» опция

- Выбранная опция определяется по `isEquivalent`: для simplified-опций равенство `source` и `seedColor` (`model/color/ColorOptionImpl.kt:134-138`). Стиль в эквивалентность не входит (комментарий `ColorOptionImpl.kt:99-101`).
- Ключ для списка: `"${source}::${seedColor}"` (`ColorPickerViewModel.kt:90-92`), для full-варианта: `"${type}::${style}::${serializedPackages}"` (`ColorPickerViewModel.kt:309-310`).

---

## 2. Иконка-swatch (круглая кнопка цвета)

### 2.1 Что рисуется (compose, основной путь)

Функция `ColorSeedOption` (`picker/color/ui/compose/ColorFloatingSheet.kt:366-463`) рисует 4 квадранта по координатам:
- TL = `lightThemeColor0` / `darkThemeColor0` (`ColorFloatingSheet.kt:393-404`);
- TR = `…1`, `Offset(w/2, 0)` (`:405-414`);
- BL = `…2`, `Offset(0, h/2)` (`:415-424`);
- BR = `…3`, `Offset(w/2, h/2)` (`:425-434`).

Ширина квадранта округляется вверх: `ceil(size.width / 2f)` (`:393`), чтобы не было щелей при bounce.

Выбор light/dark по `isDarkMode` (`:398,407,417,427`).

Цвета приходят из `ColorOptionIconViewModel.fromColorOption` → `colorOption.previewInfo.resolveColors(darkTheme)` (`picker/color/ui/viewmodel/ColorOptionIconViewModel.kt:34-46`).

Геометрия контейнера: `ColorSeedOption` имеет `Modifier.size(54dp)` (`ColorFloatingSheet.kt:291-294`, `res/values/dimens.xml:198 floating_sheet_color_option_size = 54dp`). Внутри `ColorOption` (`picker/color/ui/compose/ColorOption.kt`) — `padding(7.dp)` (`:72`), затем клип: **круг** (`CircleShape`, `:78`) для невыбранной, **скругление 12dp** для выбранной (`:74-77`).

### 2.2 Что рисуется в каждом квадранте (расчёт цветов)

Функция `ColorProviderUtil.getColorPreview` (`ColorProviderUtil.kt:180-208`):
- условие `if (!isColorPickerUpdateEnabled && colorSource == HOME || colorSource == LOCK)` — при флаге update ON (а `buildSimplifiedSeedOption` всегда передаёт `isColorPickerUpdateEnabled = true`, `ColorOptionImpl.kt:116,123`) до этого ветки **не доходит для HOME**;
- `MONOCHROMATIC` → monochrome preview (`:195-200`);
- иначе → `getLight/DarkOneOrTwoColorPreview` (`:201-207`).

`getLightOneOrTwoColorPreview` (`ColorProviderUtil.kt:296-311`):
- для стиля `FRUIT_SALAD` — `[accent3@450, accent1@550]`;
- для остальных — `[accent1@450, accent1@450]`;
- результат `[c0, c1, c0, c1]` (`:310`).

`getDarkOneOrTwoColorPreview` (`ColorProviderUtil.kt:282-290`): аналогично, `accent1.s200` (для не-FRUIT_SALAD), результат `[c0, c1, c0, c1]`.

**Вывод для текущего пути (флаг update ON, стили SPRITZ / TONAL_SPOT / VIBRANT / EXPRESSIVE)**: все четыре квадранта имеют один и тот же цвет (`accent1` на тоне 450 в светлой теме, `accent1` s200 в тёмной). То есть иконка на экране — однотонный круг, а не четыре разных квадранта. Это прямо следует из кода (`:306-307`, `:286-287`, `:310`, `:289`). Квадранты в варианте «ring/quadrants» заложены, но для текущих стилей фактически не используются.

Легаси-путь (флаг update OFF, или HOME/LOCK в старой ветке, `getColorPreview` при `darkTheme=false`):
- `getLightThreeColorPreview` (`ColorProviderUtil.kt:218-225`): TL = accent1 s600, TR = accent1 s600, BL = accent2 s500 с L*=85 (`withLStar(85f)`), BR = accent3 s300;
- `getDarkThreeColorPreview` (`:235-242`): TL = TR = accent1 s200, BL = accent2 s500 с L*=35, BR = accent3 s300.
- Monochrome (`:252-276`): `accent1.s1000` / `s10` в TL и TR, BL — accent2 с L*85/L*35, BR — accent3 s300.

Разметка «которые квадранты»: TL и TR — основной акцент, BL — secondary, BR — tertiary (комментарии `ColorProviderUtil.kt:214-216,231-233`).

### 2.3 Иконка ColorOptionIconView (XML-путь, legacy)

`picker/color/ui/view/ColorOptionIconView.kt`:
- те же 4 квадранта, те же цвета через `bindColor` (`:68-87`);
- обводка: `strokeWidth = R.dimen.floating_sheet_color_option_stroke_width = 3dp` (`:54-57`, `res/values/dimens.xml:199`), цвет `bindStrokeColor` (`:94-97`), из `colorPrimary` через `ColorUpdateBinder` (`ColorOptionIconBinder.kt:41-47`);
- скругление контейнера (`:113-120`): `cornerRadius = ((right-left)/2) * (1 - 0.25 * progress)`, `progress` 0 = светлая, 1 = тёмная. То есть светлая — круг, тёмная — скруглённый квадрат (радиус 0.75 полуширины);
- stroke-альфа = `255 * progress` (`:147`) — обводка видна только в тёмной теме;
- `darkThemeProgress` анимируется через `DarkModeUpdateBinder` (`ColorOptionIconBinder.kt:58-64`, сам биндер отсутствует).

### 2.4 Выбранная опция: кольцо и бейдж

**Кольцо выбранной** (`ColorOption.kt:55-67`): `Modifier.fillMaxSize().clip(RoundedCornerShape(18.dp)).border(width = 3.dp, color = colorScheme.primary, shape = RoundedCornerShape(18.dp)).drawBehind { drawRect(surfaceBright) }`.

Значения:
- внешний радиус 18dp (`ColorOption.kt:43`);
- толщина обводки 3dp (`:61`), цвет `primary` (`:62`);
- фон под кольцом `surfaceBright` (`:65`);
- внутренний контент: padding 7dp (`:72`), клип 12dp для выбранной (`:76`), круг для остальных.

**Бейдж «карандаш»** (ColorSeedOption, только если `enableVariantPicker = isSelected && optionItem.enableDrillDown`, `ColorFloatingSheet.kt:377,439-461`):
- размер Box 48dp (`floating_sheet_clock_edit_icon_size`, `dimens.xml:195`);
- позиция: `align(TopEnd)`, `offset(x = 15.dp, y = -15.dp)` (`ColorFloatingSheet.kt:444-445`); имя dimens `floating_sheet_clock_edit_icon_margin = -18dp` в `dimens.xml:196` не используется для этого бейджа;
- рисование: круг `surfaceBright` радиусом 18dp, поверх круг `onPrimaryFixedVariant` радиусом 14dp (`:447-451`);
- иконка `edit_icon_foreground`, tint белый, `fillMaxSize` (`:454-459`). Drawable отсутствует в срезе.

---

## 3. Панель «Your wallpaper colors» (landing sheet)

Функция `ColorFloatingSheetLanding` (`picker/color/ui/compose/ColorFloatingSheet.kt:185-345`).

Контейнер:
- `Box`: `fillMaxWidth`, `padding(horizontal = 16.dp)` (`:225-226`), `clip(RoundedCornerShape(28.dp))` (`:227`), фон `surfaceBright` (`:228`).
- Внутренний `Column`: `padding(top = 16.dp, bottom = 20.dp)` (`:230`).

Заголовок (слева):
- `Text`, `titleMedium`, цвет `onSurface` (`:244-248`).
- Текст меняется по скроллу списка через `derivedStateOf` (`:198-220`): `wallpaper_color_title_2` («Your wallpaper colors» / «Цвета обоев»), `preset_color_tab_2` («Other colors» / «Другие цвета»), `freeform_color_title` («Your colors» / «Ваши цвета»); по умолчанию `wallpaper_color_tab`. Строки: `res/values/strings.xml:437,425,434`, `values-ru/strings.xml:148,143,147`.
- Анимация смены текста: `AnimatedContent`, `fadeIn(tween(200 ms, delay 200 ms)) togetherWith fadeOut(tween(200 ms))` (`:236-242`).

Кнопка палитры (справа, переход в freeform):
- `IconButton` 32dp (`:251-252`), `containerColor = surfaceDim`, `contentColor = onSurface` (`:254-258`);
- иконка `ic_palette_filled_24px`, 20dp (`:260-264`); `contentDescription = ""`.

Ряд свотчей:
- `Spacer` 8dp (`:268`);
- `LazyRow`, `contentPadding(horizontal = 20.dp)`, `spacedBy(2.dp)`, вертикальное центрирование (`:271-279`);
- размер каждого свотча 54dp (см. §2);
- группы разделены `OptionListGroupDivider` (`:282-284,348-364`): `Box` 12×28dp, `padding(horizontal = 5.dp)`, `drawRoundRect` цвет `onSurfaceVariant` радиус 1dp, `hideFromAccessibility`.

Строка «Dark theme» (`:311-342`):
- `Spacer` 16dp перед ней (`:309`);
- `Row`: `padding(horizontal = 20.dp)`, `fillMaxWidth`, `SpaceBetween`, `CenterVertically` (`:311-314`);
- текст `mode_title` («Dark theme» / «Тёмная тема»), `titleMedium`, `onSurface` (`:316-320`; строки `values/strings.xml:402`, `values-ru/strings.xml:133`);
- `Switch` (Material 3, `androidx.compose.material3.Switch`, стили не переопределены, `:322-341`): `checked = isDarkMode`, `enabled = isDarkModeToggleEnabled`; при `checked` в thumb вставляется иконка `ic_check_wallpaper` размером `SwitchDefaults.IconSize` (`:326-337`). Цвета трека/thumb — дефолтные M3.

Тема превью: все цвета панели берутся из `LocalAnimatedColorScheme` (`ColorPreviewTheme.kt:72,84-86`), то есть перекрашиваются при смене выбранного свотча. Тёмная тема для превью — `previewingIsDarkMode` (`ColorFloatingSheet.kt:96-97,122-125`).

Раскладка иконок в свотче в dark/light: см. §2.1 (`isDarkMode` из `previewingIsDarkMode`).

Ключевой пункт для порта: кнопок ✕ и ✓ **в этой панели нет**; они появляются только в drill-down экранах (§5, §6).

---

## 4. Экран «Select a color» (freeform, FreeformColorPicker)

Файлы: `picker/color/ui/compose/FreeformColorPicker.kt:35-81`, `BrushSlider.kt:42-108`.

### 4.1 Контейнер и текст

- Внешняя обёртка — `DrillDownFloatingSheet` (см. §5).
- Внутренний `Column`: `fillMaxWidth().padding(20.dp)` (`FreeformColorPicker.kt:51`).
- Заголовок: `color_freeform_editor_description` («Select a color» / «Выбрать цвет», `res/values/strings.xml:690`, `values-ru/strings.xml:184`), `titleMedium`, `onSurface`, `TextAlign.Center`, `fillMaxWidth` (`FreeformColorPicker.kt:52-58`).

### 4.2 Градиент слайдера (hue)

Код (`FreeformColorPicker.kt:60-71`):
- `huePhaseShift = -30f`;
- `for (i in 0..360 step 30)` → 13 стопов (0, 30, …, 360);
- цвет каждого стопа: `Color.hsv(hue = (i - 30).mod(360), saturation = 0.6f, value = 0.8f)` — то есть hue начинается с 330° и идёт по кругу;
- `Brush.horizontalGradient(colors = hueColorList)` (`:73`) — равномерные стопы (`horizontalGradient` без явных offset).

Важное расхождение: **градиент рисуется в HSV (s=0.6, v=0.8)**, а **семя цвета** строится в **HCT (chroma 100, tone 80)** (`ColorProviderUtil.kt:333`). Это разные цветовые пространства. Визуальный цвет ползунка и итоговая палитра не совпадают точно (предположение: HCT(100,80) заметно ярче и насыщеннее HSV(0.6,0.8) на большинстве hue). Для порта выбрать одно правило и сверить с эталонным скриншотом.

### 4.3 Диапазон и маппинг позиции → seed

- `valueRange = 0f..360f` (`FreeformColorPicker.kt:75`) — позиция ползунка напрямую = hue в градусах.
- `HUE_INIT_VALUE = 180f` (`picker/color/ui/viewmodel/ColorPickerViewModel.kt:444`), используется, если сохранённого hue нет (`ColorPickerViewModel.kt:113,141`).
- Маппинг позиция → seed: `hueToColorOption(hue)` = `Hct.from(hue, 100.0, 80.0).toInt()` (`model/color/ColorProviderUtil.kt:333`). Тон фиксирован 80, chroma фиксирована 100. Ползунок управляет только hue.
- Стиль при выборе: `TONAL_SPOT` (`ColorProviderUtil.kt:339`). Далее его можно поменять в variant-picker.

### 4.4 Трек и thumb (BrushSlider)

`BrushSlider.kt`:
- Высота трека: `trackHeight = 28.dp` (`:49`), `Modifier.height(trackHeight)` (`:59`).
- Внешний угол (начало/конец со стороны «активной» или «неактивной» части): `trackHeight * 3 / 8` = 10.5dp (`:60`, `:76`, `:94`).
- Внутренний угол у точки thumb: 2dp (`:61`, `:77`, `:93`).
- Зазор между треком и thumb: 6dp (`:62`, `:70-86`).
- Активная часть: `[0; x_thumb - 6dp]`, неактивная: `[x_thumb + 6dp; width]` (`:66-69,82-86`). Обе части рисуются через `drawTrackPath` (`:112-143`) с `RoundRect` и `drawPath(brush)`.
- Дефолтный трек M3 скрыт: `activeTrackColor = Transparent`, `inactiveTrackColor = Transparent` (`:99-104`). Видимый трек — только gradient.
- Thumb: не переопределён (`BrushSlider.kt:51-107` использует только `track = {...}`), то есть визуальная форма — дефолтная M3 Slider thumb. Размер и форма (вертикальная полоска) — предположение по описанию пользователя и дефолтам библиотеки; в срезе значений нет.
- Ширина/высота всего слайдера: `fillMaxWidth`, высота по содержимому M3 (`FreeformColorPicker.kt:77`).

### 4.5 Live-preview

Цепочка (`picker/color/ui/viewmodel/ColorPickerViewModel.kt:109-130`, `ColorFloatingSheet.kt:92-127`):
1. Перетаскивание → `onHueChange` = `colorPickerViewModel::updateHue` → `overrideHue.value = hue` (`ColorPickerViewModel.kt:132-134`).
2. `hueSliderPosition = override ?: saved ?: 180` (`:111-114`).
3. `tempFreeformColorOption = hueSliderPosition.map(hueToColorOption)` (`:116`).
4. `tempOverridingColorOption` выбирает freeform-опцию, когда `currentScreen == FREEFORM_PICKER` (`:118-124`).
5. `tempPreviewingColorOption = overriding ?: selected` (`:126-130`).
6. `ColorFloatingSheet` строит `DynamicScheme` из `previewingColorOption.seedColor`, `previewingIsDarkMode`, `previewingStyle` (`ColorFloatingSheet.kt:121-127`) и отдаёт в `ColorPreviewTheme` (`:129`), который анимирует цвета (см. §7).

Иначе говоря, весь UI (включая панель, кнопки) перекрашивается в реальном времени от текущего hue.

Подтверждение/отмена:
- ✓ → `onConfirm = confirmFreeformColor` → `saveFreeformColor(hue)` (сохранение в prefs) и `_overridingColorOption = hueToColorOption(hue)` (`ColorPickerViewModel.kt:140-146`); затем `navigateToLanding()` (`DrillDownFloatingSheet.kt:108-113`).
- ✕ → `onCancel = cancelFreeformColor` → `overrideHue = null` (`ColorPickerViewModel.kt:136-138`); затем `navigateToLanding()` (`DrillDownFloatingSheet.kt:88-94`).
- Системная «назад» ведёт к той же отмене (`DrillDownFloatingSheet.kt:59-63`).

---

## 5. Вариант-редактор (ColorVariantPicker) и общие кнопки

### 5.1 Layout 4 вариантов

Файл: `picker/color/ui/compose/ColorVariantPicker.kt:110-251`.

- Внешняя обёртка — `DrillDownFloatingSheet`, внутренний контент — `LazyRow` (`:127-138`):
  - `Modifier.padding(vertical = 20.dp)`;
  - `contentPadding = PaddingValues(horizontal = 20.dp)`;
  - `horizontalArrangement = spacedBy(2.dp)`;
  - `verticalAlignment = CenterVertically`.
- Каждый элемент — `Column(width = 68.dp)` (`:149`):
  - `ColorOption` (тот же компонент, что и для свотчей, §2.4) с `fillMaxWidth().height(68.dp)` (`:150-153`);
  - `Spacer` 3dp (`:214`);
  - подпись `Text` с `fillMaxWidth()` (`:216-217`), `TextAlign.Center` (`:237`), цвет `onSurface` (`:236`).
- Стиль подписи: выбран — `labelSmallEmphasized`, не выбран — `labelSmall` (`:230-235`).
- Прозрачность подписи: `animateFloatAsState(if selected 1f else 0.25f)` (`:141`), применяется через `graphicsLayer { alpha }` (`:217`).

Размер варианта: 68dp × 68dp (квадратный, `:153`), подпись 3dp ниже.

Выбранный: кольцо 3dp `primary`, внешний радиус 18dp, внутренняя часть 12dp (см. §2.4). Невыбранный: круг.

Геометрия/поля в диалоге: `LazyRow` идёт на полную ширину `DrillDownFloatingSheet` внутри `padding(horizontal = 16.dp)` (`DrillDownFloatingSheet.kt:69`). То есть 20dp внутри LazyRow плюс 16dp снаружи.

### 5.2 Окраска варианта (превью стиля)

`ColorVariantPicker.kt:142-148` — `ColorScheme(previewingSeedColor, previewingIsDarkMode, option.style).materialScheme` (берётся **seed выбранной опции**, а не стиль варианта — стиль подставляется). Затем (`:169-191`):

| Стиль | background | mid-layer (квадрат) | top-layer (круг) |
|---|---|---|---|
| SPRITZ (Neutral) | `secondaryFixed` | `secondaryFixed` | `primaryFixed` |
| любой другой (Soft/Bright/Bold) | `tertiaryFixed` | `secondaryFixed` | `primaryFixed` |

Геометрия фона — AGSL-шейдер (`ColorVariantPicker.kt:61-107`, `RuntimeShader`), константы:
- `BLUR_PERCENT = 0.5` (`:70`) → `blurDist = h * 0.5` (`:87`);
- `BOX_SIZE_PERCENT = 0.5` (`:71`) → `sideLengths = (w*0.5, h*0.5)` (`:90`);
- `CIRCLE_RAD_PERCENT = 0.42` (`:72`) → радиус круга `h * 0.42` (`:97`);
- `CIRCLE_OPACITY = 0.9` (`:73`) → сила смешения круга (`:101`).

Смысл геометрии (предположение, из формул): квадрат-бокс (`sdBox`) центрирован в начале координат, то есть по сути покрывает левый-верхний угол; круг центрирован в `(w*0.58, h*0.58)`. Визуально: фон + квадрат в одном углу + круг в противоположном, размытые края (smoothstep по `blurDist`). Точная раскладка на экране должна сверяться со скриншотом.

Цвета передаются через `setColorUniform` (`:197-208`), фон рисуется через `drawRect(brush = ShaderBrush(shader))` в `onDrawBehind` (`:195-210`).

### 5.3 Кнопки ✕ и ✓ (DrillDownFloatingSheet)

Файл: `picker/color/ui/compose/DrillDownFloatingSheet.kt:50-129`.

Контейнер:
- Внешний `Column`, центр по горизонтали (`:65`).
- Блок контента: `wrapContentSize().padding(horizontal = 16.dp).clip(RoundedCornerShape(28.dp)).drawBehind { drawRect(surfaceBright) }` (`:66-71`).
- Отступ между панелью и кнопками: `Spacer` высотой `floating_sheet_tab_toolbar_vertical_margin = 8dp` (`:76-81`, `dimens.xml:186`).

Ряд кнопок (`:83-128`):
- `Row`, `CenterVertically`, `spacedBy(clock_font_apply_padding_start = 8dp)` (`:85-86`, `dimens.xml:212`).

Кнопка ✕ (cancel / revert):
- `Button`, `width(72.dp).height(56.dp)` (`:89`);
- `onClick`: `onCancel(); navigateToLanding()` (`:90-93`);
- цвета: контейнер `secondaryContainer`, контент `onSecondaryContainer` (`:94-100`), disabled — `onSurface`;
- иконка `ic_close`, 24dp (`:102-106`), `contentDescription = color_variant_editor_revert` («Undo theme style change» / «Отменить изменение темы», `values/strings.xml:683`, `values-ru/strings.xml:183`).

Кнопка ✓ (apply / confirm):
- `Button`, `width(72.dp).height(56.dp)` (`:109`);
- `onClick`: `onConfirm(); navigateToLanding()` (`:110-113`);
- цвета: контейнер `primary`, контент `onPrimary` (`:114-120`), disabled — `onSurface`;
- иконка `ic_check_wallpaper`, 24dp (`:122-126`), `contentDescription = color_variant_editor_apply` («Apply theme style change» / «Применить изменение темы», `values/strings.xml:676`, `values-ru/strings.xml:182`).

Форма кнопок: в коде не задана; `Button` использует дефолтную форму Material 3. Предположение: пилюля (полное скругление по высоте 56dp, радиус 28dp). Подтвердить по скриншоту.

Чистые размеры: 72 × 56dp; зазор 8dp.

---

## 6. Размеры и отступы — сводка (с источниками)

| Элемент | Значение | Источник |
|---|---|---|
| Свотч (сторона) | 54dp | `ColorFloatingSheet.kt:291-294`; `dimens.xml:198` |
| Кольцо выбранного | 3dp, primary | `ColorOption.kt:61-62` |
| Скругление кольца | 18dp | `ColorOption.kt:43` |
| Внутренний padding свотча | 7dp | `ColorOption.kt:72` |
| Скругление внутреннего при выборе | 12dp | `ColorOption.kt:76` |
| Бейдж карандаша | 48dp, offset (+15, −15) dp, круг 18dp+14dp | `ColorFloatingSheet.kt:441-451`; `dimens.xml:195` |
| Разделитель групп | 12×28dp, padding 5dp, радиус 1dp | `ColorFloatingSheet.kt:348-364` |
| Панель: радиус | 28dp | `ColorFloatingSheet.kt:227`; `DrillDownFloatingSheet.kt:70` |
| Панель: боковой отступ снаружи | 16dp | `ColorFloatingSheet.kt:226`; `DrillDownFloatingSheet.kt:69` |
| Панель landing: top / bottom | 16dp / 20dp | `ColorFloatingSheet.kt:230` |
| Горизонтальный отступ строк landing | 20dp | `ColorFloatingSheet.kt:232,274,312` |
| Spacer после заголовка до свотчей | 8dp | `ColorFloatingSheet.kt:268` |
| Spacer перед «Dark theme» | 16dp | `ColorFloatingSheet.kt:309` |
| Палитра-кнопка | 32dp, иконка 20dp, фон surfaceDim | `ColorFloatingSheet.kt:252-261` |
| Freeform: внутренний padding | 20dp | `FreeformColorPicker.kt:51` |
| Вариант: высота + ширина | 68dp × 68dp (колонка 68dp) | `ColorVariantPicker.kt:149,153` |
| Вариант: подпись отступ | 3dp | `ColorVariantPicker.kt:214` |
| Вариант: LazyRow | vertical 20dp, horizontal 20dp, spacing 2dp | `ColorVariantPicker.kt:134-137` |
| Слайдер: высота трека | 28dp | `BrushSlider.kt:49` |
| Слайдер: скругления | 10.5dp внешнее, 2dp внутреннее | `BrushSlider.kt:60-61` |
| Слайдер: зазор у thumb | 6dp | `BrushSlider.kt:62` |
| Кнопки ✕ ✓ | 72×56dp, spacing 8dp | `DrillDownFloatingSheet.kt:89,109,85-86` |
| Иконки кнопок | 24dp | `DrillDownFloatingSheet.kt:105,125` |
| Отступ панели → кнопки | 8dp | `DrillDownFloatingSheet.kt:76-81`; `dimens.xml:186` |
| Stroke XML-свотча | 3dp | `ColorOptionIconView.kt:54-57`; `dimens.xml:199` |

Тип шрифта: `titleMedium` (заголовки, «Dark theme», «Select a color»), `labelSmall` / `labelSmallEmphasized` (подписи вариантов). Семантика M3 Expressive. Конкретные размеры шрифтов в срезе отсутствуют.

Цветовые роли, которые используются (все M3 tokens, через `LocalAnimatedColorScheme` или `MaterialDynamicColors`):
- Панель: `surfaceBright` (фон), `onSurface`, `onSurfaceVariant` (разделитель), `surfaceDim` (кнопка палитры);
- Выбранный свотч: `primary` (кольцо), `surfaceBright` (подложка кольца);
- Кнопка ✓: `primary` / `onPrimary`; ✕: `secondaryContainer` / `onSecondaryContainer`;
- Бейдж: `surfaceBright`, `onPrimaryFixedVariant`, иконка белая;
- Вариант: `tertiaryFixed` / `secondaryFixed` / `primaryFixed` (через `MaterialDynamicColors`, см. §5.2);
- Переключатель dark theme: Material 3 дефолт (цвета не переопределены).

---

## 7. Анимации

| Что | Значение | Источник |
|---|---|---|
| Смена экранов landing ↔ variant ↔ freeform | `AnimatedContent`, `fadeIn() togetherWith fadeOut()`; длительность и кривая не заданы, дефолт библиотеки | `ColorFloatingSheet.kt:130-133` (дефолт Compose — предположение: `tween` ~300 мс, FastOutSlowIn) |
| Смена заголовка landing | `fadeIn(tween(200 ms, delay 200 ms)) togetherWith fadeOut(tween(200 ms))` | `ColorFloatingSheet.kt:238-242` |
| Перекраска цветов (палитра превью) | `animateColor(tween(COLOR_ANIMATION_DURATION_MILLIS, LinearEasing))` — значение константы не определено в срезе | `ColorPreviewTheme.kt:127-140` |
| Альфа подписи варианта | `animateFloatAsState(1f / 0.25f)`, дефолтная spring (предположение: dampingRatio 1, stiffness 1500) | `ColorVariantPicker.kt:141,217` |
| Bounce нажатия (свотчи, варианты) | `bounceable(...)` + `clickBounceAnimate()`; параметры в срезе не определены | `ColorVariantPicker.kt:154-167`; `ColorFloatingSheet.kt:295-303,387` |
| Ожидание обновления системных цветов после apply | таймаут `3000 ms`; apply ждёт первого события `systemColorsUpdatedNoReplay` | `ColorPickerViewModel.kt:399-404,443` |
| Смена light/dark (legacy XML-свотч) | `darkThemeProgress` 0..1 по `DarkModeUpdateBinder`; радиус `(1 - 0.25*progress)`, альфа stroke `255*progress` | `ColorOptionIconView.kt:89-92,117,147`; `ColorOptionIconBinder.kt:58-64` |
| Переключатель Dark theme | Material 3 `Switch` дефолтная анимация (не переопределена) | `ColorFloatingSheet.kt:322-341` |
| Слайдер hue | дефолтная анимация M3 Slider; перетаскивание без easing | `BrushSlider.kt:51-107` |

Полезно для порта: единственная явная длительность в срезе — 200 мс для текста заголовка (с 200 мс задержкой на появление). Длительность перекраски цветов спрятана в отсутствующем `ColorUpdateViewModel`.

---

## 8. Поток данных (для проектирования на UIKit)

Короткая схема, чтобы не потерять связь между слоями:

1. Repository (`ColorPickerRepositoryImpl.kt:200-214`) собирает список `(ColorType, [ColorOption])`: FREEFORM (если compose включён) → WALLPAPER → PRESET.
2. ViewModel (`ColorPickerViewModel.kt:206-229, 293-334, 426-433`) строит `ColorOptionViewModel` / `OptionItemViewModel2` и хранит `_overridingColorOption` (то, что выбрано, но не подтверждено на landing) и `_overridingStyle` / `_tempOverridingStyle` (для variant).
3. Экраны: `Screen { LANDING, VARIANT_PICKER, FREEFORM_PICKER }` (`ColorPickerViewModel.kt:94-99`).
4. Подтверждение:
   - landing: клик по свотчу → `_overridingColorOption` (нет confirm, подтверждения нет; apply делается через `onApply`, `ColorPickerViewModel.kt:340-368`);
   - variant: тап по стилю → `_tempOverridingStyle`; ✓ → `_overridingStyle`, ✕ → сброс temp (`ColorPickerViewModel.kt:188-199`);
   - freeform: ✓ → сохраняет hue и seed; ✕ → сброс `overrideHue` (`ColorPickerViewModel.kt:132-146`).
5. Применение: `onApply` в `ColorPickerViewModel.kt:340-368` и `ColorPickerRepositoryImpl.kt:338-406` (`apply(colorOption, style)` использует `buildSimplifiedSeedOption` при theme service, иначе `buildPreset`/`buildBundle`).
6. Для theme service: `ThemeSettings.Builder().setSeedColors(...).setThemeStyle(...).setColorSource(...)` (`ColorPickerRepositoryImpl.kt:340-348`).

Точки, которые нельзя терять при порте:
- seed = один `Int` (ARGB), полный набор ролей считается из `seed + style + isDark`;
- freeform seed = `Hct(hue, 100, 80)`, не HSV;
- варианты влияют только на стиль, seed сохраняется.

---

## 9. Открытые вопросы и расхождения

1. Квадранты на свотче при текущих флагах фактически однотонные (§2.2). Проверить на устройстве, какой флаг включён (`BaseFlags.isColorPickerUpdateEnabled`). Если OFF — будет 3-цветный вариант.
2. Градиент слайдера (HSV 0.6/0.8) ≠ seed (HCT 100/80) (§4.2). Нужно решить, какой цвет показывать на треке.
3. Длительность перекраски (`COLOR_ANIMATION_DURATION_MILLIS`) и bounce-параметры — в отсутствующих файлах. Для порта можно взять предварительное значение, но оно не подтверждено.
4. Форма кнопок ✕/✓ (пилюля) — дефолт M3, не задан в срезе.
5. Превью-карточка телефона и её вёрстка в этом срезе отсутствуют (§0).
6. Точное значение стилизации thumb слайдера — дефолт M3 (§4.4).
