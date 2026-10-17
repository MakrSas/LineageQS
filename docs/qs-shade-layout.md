# Layout и внешний вид шторки и Quick Settings (Android 17 / LineageOS 24.0), портрет телефона

Исследование только чтения. Ни один исходный файл не изменялся.

## Соглашения

- Базовый путь всех ссылок `upstream/lineage-frameworks-base/`. Для SystemUI дальше указан путь от `packages/SystemUI/`.
- `file:line` дан для каждого значения. `[CONF]` означает, что значение прочитано из кода или ресурса в клоне. `[ПРЕД]` означает предположение, которое не проверено по коду.
- Размеры в dp и sp даны как в ресурсах. Пиксели не пересчитывались.
- Ориентир «телефон»: ширина < 600dp (compact). Все проверки ниже относятся к этому случаю, если не сказано иное.
- Если в клоне нет значения (например, RGB-значения `shade_panel_*_color`), это отмечено явно.

---

## 0. Что по умолчанию на телефоне (ответ на пункт 5)

### 0.1 Что подтверждено кодом

1. Dual Shade включается только когда одновременно включены оба флага:
   - `DualShadeFlag.isEnabled = (dualShade() || isDesktopDevice) && SceneContainerFlag.isEnabled` — `packages/SystemUI/src/com/android/systemui/shade/shared/flag/DualShadeFlag.kt:42-43`.
   - `SceneContainerFlag.isEnabled = sceneContainer() && isEnabledOnVariant` — `packages/SystemUI/src/com/android/systemui/scene/shared/flag/SceneContainerFlag.kt:41-43`.
   - Флаги в `packages/SystemUI/aconfig/systemui.aconfig`: `dual_shade` — строки 355-360 (`name` в 356); `scene_container` — строки 1469-1473 (`name` в 1470). Значения по умолчанию в aconfig не заданы, поэтому релизное значение в этом файле не видно.

2. Если Dual Shade выключен, режим шторки берётся из ширины: `isFullWidth ? Single : Split` (`packages/SystemUI/src/com/android/systemui/shade/domain/interactor/ShadeModeInteractor.kt:158-166`). `isFullWidth` в этом случае берётся из `legacyUseSplitShade` (`ShadeModeInteractor.kt:118-133`, `ShadeConfigRepository.kt:105-116`). На телефоне `config_use_split_notification_shade = false` (`packages/SystemUI/res/values/config.xml:682`), поэтому режим — **Single** (классическая шторка с уведомлениями под QS).

3. Если Dual Shade включён, режим выбирается так (`ShadeModeInteractor.kt:86-112`, `ShadeConfigRepository.kt:65-82, 90-91`):
   - Если `config_useDualShadeSetting = true` (`packages/SettingsLib/res/values/config.xml:62`; для sw600dp — `false`, см. `packages/SettingsLib/res/values-sw600dp/config.xml:20`), то берётся пользовательская настройка `Settings.Secure.DUAL_SHADE` с значением по умолчанию `config_dualShadeEnabledByDefault`.
   - `config_dualShadeEnabledByDefault = true` (`packages/SystemUI/res/values/shade_config.xml:39`).
   - Итог: **при включённых обоих флагах телефон по умолчанию получает Dual**. Пользователь может переключить это в Settings, если `config_useDualShadeSetting = true`.

4. Комментарий в коде подтверждает, что Compose «SingleShade» используется и в Dual, а переключением сцен занимается ViewModel: `packages/SystemUI/compose/features/src/com/android/systemui/shade/ui/composable/ShadeScene.kt:258-260`.

5. Lineage-переопределений `config_dualShadeEnabledByDefault`, `config_isFullWidthShade` и `config_use_split_notification_shade` в клоне нет. Grep по всему `upstream/` нашёл только AOSP-значения. Файлы `packages/SystemUI/res/values/lineage_config.xml` и `lineage_dimens.xml` не содержат ничего относящегося к шторке (UDFPS, doze, screen recorder, аватар global actions).

6. Размеры ширины по конфигу: `config_isFullWidthShade = true` (`packages/SystemUI/res/values/shade_config.xml:26`). Значение `false` задано только для `w600dp` (`packages/SystemUI/res/values-w600dp/shade_config.xml:19`). На телефоне шторка full-width.

7. Жест на Dual: свайп вниз от левой части экрана (до 0.75 ширины) открывает уведомления, от правой — QS (`packages/SystemUI/res/values/shade_config.xml:57`, комментарий в строках 47-56).

### 0.2 Чего не видно в клоне (ПРЕД)

- Релизные значения `dual_shade` и `scene_container` на Android 17 / LineageOS 24 находятся в релизной конфигурации (`build/release/...`), которой в клоне нет. Поэтому по коду **нельзя** утверждать, что по умолчанию включено. Если оба флага включены, телефон по умолчанию в Dual. Если хотя бы один выключен, телефон в Single.
- Вывод для iOS-порта: проектировать и Single (классическая шторка), и Dual. Для Single нужен только верхний ряд уведомлений и QQS под ним. Для Dual нужны два отдельных overlay-листа.

---

## 1. Шапка шторки (Shade header)

Файл: `packages/SystemUI/compose/features/src/com/android/systemui/shade/ui/composable/ShadeHeader.kt`.

### 1.1 Общие размеры и цвета [CONF]

| Что | Значение | Где |
|---|---|---|
| Высота шапки в развёрнутом виде `ExpandedHeight` | 120dp (минимальная высота колонки) | `ShadeHeader.kt:158, 312` |
| Chip padding horizontal / vertical | 6dp / 4dp | `ShadeHeader.kt:159-160` |
| Высота шапки для переходов (устарело) | 48dp | `ShadeHeader.kt:157` |
| Цвет текста шапки | чёрный (light), белый (dark) | `ShadeHeader.kt:167` (`if isSystemInDarkTheme() White else Black`) |
| Обратный цвет (для чипов) | белый (light), чёрный (dark) | `ShadeHeader.kt:172` |
| Горизонтальный отступ `Shade.Dimensions.HorizontalPadding` | 16dp | `ShadeScene.kt:133` |
| Итоговый отступ шапки (collapsed) | `max(cornerRadius / 2, 16dp)` | `ShadeHeader.kt:189-190` |
| Высота collapsed-шапки | `max(cutoutHeight + cutoutTop*2, statusBarHeightPx)`; без выреза = `statusBarHeightPx` | `ShadeHeader.kt:534-535` |
| Высота status bar по умолчанию | 24dp (portrait) | `core/res/res/values/dimens.xml:44, 48, 52` (относительно `upstream/lineage-frameworks-base/`) |

### 1.2 Collapsed header (шапка над QQS на телефоне) [CONF]

Компонент `CollapsedShadeHeader` (`ShadeHeader.kt:182-282`), используется в `ShadeScene.kt:362-368` и в `QuickSettingsScene.kt:419-421` (ширина ≥ 600dp).

- **Слева:** Row со spacing 5dp (`ShadeHeader.kt:208`):
  - Clock: `Clock` view на базе `Theme.SystemUI.QuickSettings.Header` (`ShadeHeader.kt:611-613`). Шрифт `variable-body-medium-emphasized` (`packages/SystemUI/res/values/styles.xml:692-696`). Размер берётся из `status_bar_clock_size = 14sp` (`packages/SystemUI/res/values/dimens.xml:179`, применение `packages/SystemUI/src/com/android/systemui/statusbar/policy/Clock.java:336`). Минимальная зона нажатия 48x48dp (`ShadeHeader.kt:218`). Выравнивание: START + CENTER_VERTICAL (`ShadeHeader.kt:620`).
  - Дата: `VariableDayDate` (`ShadeHeader.kt:221-226`). Стиль по умолчанию `MaterialTheme.typography.bodyMediumEmphasized` = 14sp / lineHeight 20sp, шрифт `variable-body-medium-emphasized` (`packages/SystemUI/compose/core/src/com/android/compose/theme/typography/TypeScaleTokens.kt:28-29`, `TypographyTokens.kt:38-39`). Текст выбирается из двух вариантов: длинный (`longerDateText`) или короткий (`shorterDateText`). Тот, что помещается по ширине, выбирается автоматически (`compose/features/src/com/android/systemui/shade/ui/composable/VariableDayDate.kt:52-88`). Шаблоны строк берутся в `ClockInteractor.kt:146-147` из `R.string.abbrev_wday_month_day_no_year_alarm` и `R.string.abbrev_month_day_no_year`. **Сами строки в клоне отсутствуют** (`core/res/res/values/strings.xml` не содержит их). Значит точные шаблоны даты (например, «Пн, 17 окт.») не проверены.

- **Справа:** Row (`ShadeHeader.kt:244-278`):
  - Если видна privacy-иконка, она заменяет правую группу (`ShadeHeader.kt:229-242`). Privacy chip располагается в `Box` с горизонтальным padding (`ShadeHeader.kt:231-236`).
  - Иначе: `ShadeHighlightChip` (`ShadeHeader.kt:255-277`). Внутри `StatusIcons` с `paddingEnd = 3sp` (`ShadeHeader.kt:259-266`), затем `BatteryInfo` с вертикальным padding 8dp только в портрете (`ShadeHeader.kt:267-276`).
  - Иконки статуса: размер рисунка `status_bar_icon_drawing_size = 15dp` (`packages/SystemUI/res/values/dimens.xml:445`).
  - Батарея: высота `status_bar_battery_icon_height = 13.0sp`, ширина `status_bar_battery_icon_width = 7.8sp` (`packages/SystemUI/res/values/dimens.xml:162, 166`), spacing 4dp (`packages/SystemUI/src/com/android/systemui/statusbar/pipeline/battery/ui/composable/BatteryWithEstimate.kt:54`). В collapsed-шапке формат оценки батареи зависит от `useExpandedTextFormat` (`ShadeHeader.kt:192-197, 270`): он включается при не-центральном вырезе или при `shouldUseExpandedFormat(layoutState)`. Значит, на обычном телефоне без выреза по центру оценка скрыта.

- **Форма и цвет chip** (`ShadeHighlightChip.kt:114-177`): круглая капсула (`CircleShape`, строка 156), фон и ripple задаются `ChipHighlightModel`.
  - `Weak`: белый с альфой 0.4 (light) или 0.1 (dark) (`ShadeHighlightChip.kt:71-83`).
  - `Strong`: `colorScheme.secondary` с `onSecondary` (`ShadeHighlightChip.kt:85-97`).
  - `Transparent`: прозрачный фон, `onSurface` (`ShadeHighlightChip.kt:99-111`).

### 1.3 Expanded header (шапка над QS на телефоне) [CONF]

Компонент `ExpandedShadeHeader` (`ShadeHeader.kt:286-366`), используется при ширине < 600dp в `QuickSettingsScene.kt:423-427`.

- Контейнер: `Column`, spacing 16dp, выравнивание снизу, `minHeight = 120dp` (`ShadeHeader.kt:309, 312`).
- Строка 1: Clock с масштабом `2.57f` (`ShadeHeader.kt:317`). Масштаб задаётся через `graphicsLayer`, origin — левый верхний угол (`ShadeHeader.kt:647-658`). Расчёт: 14sp × 2.57 ≈ 36sp [ПРЕД, рассчитано, не измерено]. Справа — carrier, ширина `widthIn(max = 180.dp)` (`ShadeHeader.kt:331`). Он показывается, только если privacy chip не виден (`ShadeHeader.kt:324-334`).
- Строка 2: `VariableDayDate` слева (`ShadeHeader.kt:341-346`) и chip справа (`ShadeHeader.kt:347-362`). Внутри: `StatusIcons`, затем `BatteryInfo` с `useExpandedFormat = true` (`ShadeHeader.kt:359`) — батарея показывает оценку времени.
- Privacy chip в expanded: `Box` высотой `statusBarHeightPx` (`ShadeHeader.kt:294-299`).

### 1.4 Carrier text [CONF]

- Одна SIM / без sub id: `Text` с `variable-body-medium-emphasized`, `letterSpacing = 0.01em`, `maxLines = 1`, `basicMarquee` (`ShadeHeader.kt:727-741`).
- Несколько SIM: `ModernShadeCarrierGroupMobileView` с стилем `TextAppearance.QS.Status` (`ShadeHeader.kt:703-725`).
- Стиль `TextAppearance.QS.Status`: шрифт `variable-body-medium-emphasized`, `letterSpacing 0.01`, `textSize = status_bar_shade_header_text_size_sp` (`packages/SystemUI/res/values/styles.xml:164-169`). Значение `14sp` (`packages/SystemUI/res/values/dimens.xml:1860`). Для sw1500dp и sw1900dp — 21sp и 28sp (`values-sw1500dp-110dpi/status-bar-dimens.xml:183`, `values-sw1900dp-90dpi/...:183`); на телефоне не применяется.
- Цвет: `shade_header_text_color` = `#FF000000` (light, `packages/SystemUI/res/values/colors.xml:28`) и `#FFFFFFFF` (dark, `packages/SystemUI/res/values-night/colors.xml:25`).
- Spacing группы SIM = 5dp (`ShadeHeader.kt:754`).

### 1.5 Шапка QS-overlay (Dual Shade, QS-лист) [CONF]

- `QuickSettingsOverlayHeader` — Row SpaceBetween: carrier слева, батарея справа без иконки, в expanded-формате (`ShadeHeader.kt:478-486`).
- `QuickSettingsOverlayPrivacyChip` — высота 48dp, по центру (`ShadeHeader.kt:489-503`, строка 495). Показывается только если включён `groupedPrivacyChip`.
- `OverlayShadeHeader` для шторки уведомлений и QS (`ShadeHeader.kt:373-474`):
  - Горизонтальный отступ = `max(cornerRadius / 2, 16dp, panelPaddingHorizontal)` (`ShadeHeader.kt:380-385`).
  - Левая часть — chip уведомлений (`notificationsHighlight`), внутри часы (только если `showClock`) и дата (`ShadeHeader.kt:391-419`).
  - Правая часть — chip QS со стилем `Strong` (`ShadeHeader.kt:428-459`, в `QuickSettingsShadeOverlay.kt:221-225`).

### 1.6 Ключевые неподтверждённые значения шапки

- Точный шаблон даты (строки `abbrev_*`) не находится в клоне.
- Высота cutout и ширина вырезов не определены (Dynamic Island / notch не моделируются). Ориентир — 24dp status bar и 16dp отступ.
- Множитель 2.57 применяется поверх базового размера 14sp `[CONF]`. Итоговый размер на устройстве не измерялся.

---

## 2. Яркость (Brightness slider) [CONF]

Compose-компонент: `packages/SystemUI/src/com/android/systemui/brightness/ui/compose/BrightnessSlider.kt`.

### 2.1 Размеры по умолчанию

- `BrightnessSliderDimensions.Default` (`BrightnessSlider.kt:581-591`):
  - иконка 28dp × 28dp;
  - thumb 52dp (высота) × 4dp (ширина);
  - track 40dp;
  - вертикальный padding 6dp;
  - скругление фона 24dp;
  - рамка фона 10dp (ширина) × 6dp (высота).
- Экран QS-overlay использует значения из `packages/SystemUI/res/values/shade_dimens.xml:43-50` (те же значения: 28dp, 52dp, 4dp, 40dp, 6dp, 24dp, 10dp, 6dp). Код: `compose/features/.../qs/ui/composable/QuickSettingsShadeOverlay.kt:520-534`.
- Внутренние константы (`BrightnessSlider.kt:595-599`):
  - скругление track: 12dp (`:596`);
  - отступ иконки внутри track: 6dp (`:597`);
  - зазор между thumb и track: 6dp (`:598`, применяется в `:367`).
- Внутреннее скругление track: 2dp (`BrightnessSlider.kt:365`).
- Высота track: `trackHeight` (`BrightnessSlider.kt:328`).
- Thumb: `DpSize(thumbWidth, thumbHeight)` (`BrightnessSlider.kt:283-290`).

### 2.2 Цвета [CONF]

- Цвета из `packages/SystemUI/pods/common/shared/colors/src/api/SystemUISliderColors.kt:25-35`:
  - track неактивный — `LocalAndroidColorScheme.current.surfaceEffect1` (`:31`);
  - активная иконка (tick) — `colorScheme.onPrimary` (`:32`);
  - неактивная иконка (tick) — `colorScheme.onSurface` (`:33`);
  - thumb и остальные цвета — `SliderDefaults.colors()` (Material 3, `:29`).
- Фон контейнера (`ContainerColors`, `BrightnessSlider.kt:561-568`):
  - по умолчанию — `colorResource(R.color.shade_panel_fallback)` (`:566`). Значение: `system_accent2_200` (light, `packages/SystemUI/res/values/colors.xml:43`), `system_accent2_800` (dark, `values-night/colors.xml:133`);
  - в QS-шторке idle = прозрачный, mirror = цвет панели (`QuickSettingsShadeOverlay.kt:411-416`).
- При перетаскивании фон меняется на `mirrorColor`, анимация `animateColorAsState` (`BrightnessSlider.kt:490-497`).

### 2.3 Иконка

- Иконка выбирается по процентам яркости: `iconResProvider(percentage)` (`BrightnessSlider.kt:170-177`, `BrightnessSliderViewModel::getIconForPercentage`). Набор иконок в `BrightnessSliderViewModel` не проверялся.
- Иконка рисуется внутри track, справа (активная или неактивная часть, `BrightnessSlider.kt:329-362`). Иконка появляется в активной части, когда её достаточно места.

### 2.4 Автояркость (Lineage-специфика) [CONF]

- Кнопка Auto: круг 52dp с clip `CircleShape` (`BrightnessSlider.kt:441-447`, размер в `:444`). Расстояние от слайдера — spacer 10dp (`:373-374`).
  - Включена: фон `colorScheme.primary`, иконка `onPrimary`, рисунок `ic_qs_brightness_auto_on` (`:421-439`).
  - Выключена: фон `LocalAndroidColorScheme.current.surfaceEffect1`, иконка `onSurface`, рисунок `ic_qs_brightness_auto_off`.
- Видимость: `config_automatic_brightness_available` (`:215-217`) **и** Lineage-настройка `QS_SHOW_AUTO_BRIGHTNESS` (`:218-232`, чтение `:405-413`).
- Значение `QS_SHOW_AUTO_BRIGHTNESS` по умолчанию = **1** (`BrightnessSlider.kt:409-410`). Ключ объявлен в `upstream/lineage-sdk/sdk/src/java/lineageos/providers/LineageSettings.java:2735` (`"qs_show_auto_brightness"`).

### 2.5 Положение слайдера в QS (контейнер)

- В QS-сцене (`QuickSettingsContent.kt:58-87`) слайдер имеет вертикальный padding `qs_brightness_margin_top = 8dp` (`packages/SystemUI/res/values/dimens.xml:708`, использование `QuickSettingsContent.kt:77-84`). Внутренний padding 6dp (`BrightnessSlider.kt:503`).
- В QS-overlay (Dual) — отдельный контейнер, `Modifier.fillMaxWidth()` и отступы из колонки (`QuickSettingsShadeOverlay.kt:403-420`).
- Порядок элементов:
  - QS-сцена / Single: `brightness → tiles → media` (`QuickSettingsContent.kt:134-168`);
  - QQS (шапка Single): `tiles → media` (`ShadeScene.kt:478-501`);
  - Dual-overlay: `media → brightness → volume → tiles → build number` (`QuickSettingsShadeOverlay.kt:389-501`).

### 2.6 Lineage-настройки в легаси-QS (QSFragmentCompose)

- `QS_BRIGHTNESS_SLIDER_POSITION` (0 = сверху, иначе снизу) и `QS_SHOW_BRIGHTNESS_SLIDER` (по умолчанию 1): `packages/SystemUI/src/com/android/systemui/qs/composefragment/QSFragmentCompose.kt:1570-1585`. Ключи в `lineage-sdk/.../LineageSettings.java:2729` и `1740`/`2721`.
- Режим `showSlider == 2` выводит слайдер в панель QS, `!= 0` — в QQS (`QSFragmentCompose.kt:1453, 1470, 1493, 1507`). Смысл значения 1 в клоне не документирован [ПРЕД].

---

## 3. Футер и кнопки под плитками (Footer)

### 3.1 Футер QS (сцена QS и Single-шторка) [CONF]

Файл: `packages/SystemUI/compose/features/src/com/android/systemui/qs/footer/ui/compose/FooterActions.kt`.

- Размещение: `QuickSettingsScene.kt:439-447` и `ShadeScene.kt:652-659` (Split). Отступ по горизонтали `shadeHorizontalPadding` = 0dp на телефоне (`QuickSettingsScene.kt:361-362`, `packages/SystemUI/res/values/dimens.xml:627`).
- Отступы строки (`FooterActions.kt:201-212`):
  - горизонтальные — `qs_content_horizontal_padding` = 16dp (`dimens.xml:724`, значение через `notification_shade_content_margin_horizontal` в `dimens.xml:809`);
  - сверху 8dp (`dimens.xml:563`), снизу 4dp (`dimens.xml:564`);
  - компенсация 4dp (`FooterActions.kt:218`, `dimens.xml:562`), строка сдвигается на −4dp.
- Фон (`FooterActions.kt:187-199`): при выключенном `notificationShadeBlur` — `underSurface`, скругление сверху `qs_corner_radius` = 28dp (`FooterActions.kt:191`, `dimens.xml:705`). При включённом — прозрачный.
- Кнопки в порядке слева направо (`FooterActions.kt:234-266`):
  1. текстовая кнопка (security / FGS), `weight(1f)` (`:241-244`);
  2. число FGS (если текст не показан) (`:247-250`);
  3. переключатель пользователя (`:252-256`);
  4. настройки (`:257-261`, иконка `ic_qs_footer_settings`, `FooterActionsButtonViewModel.kt:57`);
  5. питание (`:262-266`, иконка `ic_qs_footer_power`, `FooterActionsButtonViewModel.kt:73`).
- Размер кнопки: высота 40dp (`FooterActions.kt:677`, `FooterButtonHeight`); круг (`CircleShape`), иконка 20dp (`:396`).
- Текстовая кнопка: высота 40dp, масштаб по Y 0.2 → 1 (`FooterActions.kt:292-297`, `675`), fade 83ms (`:676`), горизонтальный padding 4dp (`:304`).
- Число FGS: шрифт 18sp (`FooterActions.kt:453`), `bodyLarge`.
- Кнопки «редактировать» (карандаш) в футере нет. Она находится в тулбаре QS-overlay (см. 3.2, `Toolbar.kt:159`).

### 3.2 Тулбар QS-overlay (Dual Shade) [CONF]

Файл: `packages/SystemUI/src/com/android/systemui/qs/panels/ui/compose/toolbar/Toolbar.kt`.

- Высота тулбара 48dp (`compose/features/.../QuickSettingsShadeOverlay.kt:381`, `shade_dimens.xml:51`).
- Состав (`Toolbar.kt:98-160`):
  - power-toggle (если `useInlinePowerMenu`, строка 119) либо кнопка питания (строка 131);
  - переключатель пользователя (строка 149);
  - кнопка редактирования (строка 159);
  - настройки (строка 162).
- Размеры (`Toolbar.kt:188-230, 353-365`, `shade_dimens.xml:71-75`):
  - минимальный размер кнопки 48dp (`toolbar_button_size`);
  - иконка 24dp (`toolbar_button_icon_size`);
  - подложка цветной кнопки 36dp (`toolbar_button_colored_background_size`).
- Цвет подложки: кнопка user-переключателя помечена `useIconColorProtection = true` (`Toolbar.kt:149-153`). Кнопка настроек громкости в overlay использует `containerColor = primary`, `contentColor = onPrimary` (`QuickSettingsShadeOverlay.kt:458-462`). Это отдельная кнопка, не тулбар.
- Отступы: `toolbar_bottom_padding` = 8dp (`shade_dimens.xml:72`), используется как `ToolbarBottomPadding`. Отступ вокруг шапки и тулбара — `ShortPadding = 8dp` (`QuickSettingsShadeOverlay.kt:360, 366, 371`).

### 3.3 Номер сборки (build number) [CONF]

- `BuildNumber` показывается, если `buildNumberViewModel.buildNumber != null` (`QuickSettingsShadeOverlay.kt:488-501`, вызов в `:495`).
- Расположение: в колонке QS-overlay, выравнивание по левому краю, `padding(start = 16dp)` (`:497-499`), сверху отступ 8dp (`:494`). Шрифт и цвет `BuildNumber` не проверены.

### 3.4 Индикатор страниц (page indicator)

- Размеры: ширина 16dp, высота 8dp, ширина точки 6.4dp (`packages/SystemUI/res/values/dimens.xml:727-732`).
- Класс `packages/SystemUI/src/com/android/systemui/qs/PageIndicator.java` существует.
- В Compose-пути (`QuickSettingsContent.kt`, `TileGrid`) индикатор не найден [ПРЕД, по grep]. Вероятно, пейджинг в легаси-QS.

---

## 4. Фон панели, scrim, blur, Media (пункт 4)

### 4.1 Фон шторки [CONF / частично]

- Фон Single-шторки: сплошной `ShadePanelScrim` на весь экран (`ShadeScene.kt:348`, `ShadePanelScrim.kt:33-43`). Скругления панели нет.
- Фон overlay-листа (Dual): `OverlayShade.Colors.panelBackground` = `shadePanel(withScrim = false)` (`OverlayShade.kt:233-243`).
- Логика цвета (`packages/SystemUI/src/com/android/systemui/shade/ui/ShadeColors.kt`):
  - если blur поддерживается: `composite(shade_panel_fg, shade_panel_bg)` (`ShadeColors.kt:89-95`); для scrim дополнительно композитится `shade_panel_scrim` (`:58-63`, `:33-43`);
  - иначе: `shade_panel_fallback` (`ShadeColors.kt:98-100`).
- Значения `shade_panel_fg`, `shade_panel_bg`, `shade_panel_scrim` объявлены в `core/res/res/values/colors.xml:976-978` как ссылки на `shade_panel_*_color`. **Сами `*_color` в клоне отсутствуют** (grep по `upstream/` не нашёл их). Итоговые RGB-значения не подтверждены.
- Fallback: `shade_panel_fallback` = `system_accent2_200` (light, `packages/SystemUI/res/values/colors.xml:43`), `system_accent2_800` (dark, `values-night/colors.xml:133`). Итоговые HEX — динамические (Material You), в клоне не заданы.
- Системные поверхности (для справки): `system_surface_effect_0_light = #D9E2FF`, `system_surface_effect_1_light = #FAF8FE`, `system_surface_effect_0_dark = #223050` (`core/res/res/values/colors.xml:854, 858, 908`).

### 4.2 Скругления и размеры панели [CONF]

- Ширина панели: `shade_panel_width = 600dp` (`packages/SystemUI/res/values/shade_dimens.xml:20`, `OverlayShade.kt:257-258`, `:111`). Это максимум для широких экранов.
- Горизонтальный отступ от края: `shade_panel_margin_horizontal = 0dp` на компактных экранах (`shade_dimens.xml:26`, `OverlayShade.kt:252-255`).
- Радиус скругления панели: `overlay_shade_panel_shape_radius = 46dp` (`shade_dimens.xml:28`, `OverlayShade.kt:247-250`).
- Скругления: при `isFloating` (не full-width) сверху и снизу. Иначе сверху 0, снизу `min(радиус, высота)` (`OverlayShade.kt:116-124`).
- На телефоне `isFullWidth = true`, поэтому панель не плавающая. Радиус 46dp появляется только на `w600dp`.
- Qs corner radius (футер, карточки) = 28dp (`dimens.xml:705`).
- Для Single радиуса нет (шторка на весь экран, `ShadePanelScrim.kt`).

### 4.3 Scrim

- Scrim позади overlay (шторки уведомлений и QS): `OverlayShade.Colors.ScrimBackground = shadePanelScrimBehind` (`OverlayShade.kt:227-231`). Альфа анимируется при переходе, её конечное значение в коде не задано [ПРЕД: задаётся в motion-spec, не проверено].
- Scrim в сцене Single: `ShadePanelScrim` с `shadePanel(withScrim = true)` (`ShadePanelScrim.kt:45-57`).
- Scrim для уведомлений (классическая шторка): `notification_scrim_base` (`packages/SystemUI/res/values/colors.xml:40` = `system_accent1_100`; dark `values-night/colors.xml:130` = `system_accent1_800`) с альфой **0.5** (`ShadeColors.kt:103-108`).
- Blur:
  - флаг `notification_shade_blur` (`aconfig/systemui.aconfig:1181-1186`) включает `isTransparencyEnabled` (`ShadeSceneContentViewModel.kt:89-93`);
  - блюр сцены шторки применяется **только** при открытом bouncer (`ShadeSceneContentViewModel.kt:172-180`);
  - радиус = `max_window_blur_radius = 23px` (`packages/SystemUI/res/values/dimens.xml:1286`).
- Блюр overlay QS такой же: `QuickSettingsShadeOverlayContentViewModel.kt:141`.

### 4.4 Media carousel (только позиция)

- Single, QQS-шапка: Media под плитками QQS, spacing 16dp (`ShadeScene.kt:369-431, 496`). В landscape (`mediaInRow`) — рядом, spacing `qs_tile_margin_vertical = 8dp` (`ShadeScene.kt:486-494`, `dimens.xml:706-707`).
- QS-сцена: brightness → tiles → media (`QuickSettingsContent.kt:134-168`). Spacing `QuickSettingsShade.Dimensions.VerticalPadding = 16dp` (`shade_dimens.xml:56`).
- QS-overlay (Dual): media идёт **первым** в колонке, над brightness (`QuickSettingsShadeOverlay.kt:389-400`), с вертикальным spacing 16dp (`:400`).
- Горизонтальный отступ QS-контента: `qs_horizontal_margin = 16dp` (`dimens.xml:719`, `QuickSettingsContent.kt:126-130`).

---

## 5. Классическая шторка (легаси, без scene container)

- `notification_panel_margin_top = 0dp` (`packages/SystemUI/res/values/dimens.xml:609`).
- `notification_panel_margin_bottom = 32dp` (`dimens.xml:618`), используется в `StackScrollAlgorithm.java:130`.
- `notification_side_paddings_single = 16dp` (`dimens.xml:314`).
- Заголовок QS легаси (`res/layout/combined_qs_header.xml:27-32`): высота `qs_header_height` = 24dp (`dimens.xml:746` → `status_bar_height`), горизонтальный padding `qs_panel_padding` = 16dp (`dimens.xml:734`).
- `qs_panel_padding_top = 80dp` (`dimens.xml:735`) — где применяется, не проверено [ПРЕД].
- `quick_qs_offset_height = 48dp` (`upstream/lineage-frameworks-base/core/res/res/values/dimens.xml:60`) — используется в `QSUtils.kt` и `QQSGestureListener.kt:59`.
- Порядок: уведомления идут под QS, так же как в Single.

---

## 6. Lineage-специфика (пункт «Lineage-overrides»)

Все найденные места подтверждены в коде. Файлов с layout-значениями шторки в Lineage-оверлеях в клоне нет.

| Что | Где | Значение |
|---|---|---|
| Показ авто-яркости | `brightness/ui/compose/BrightnessSlider.kt:218-232, 405-413` | `qs_show_auto_brightness`, по умолчанию 1 |
| Положение и показ слайдера яркости (легаси QS) | `qs/composefragment/QSFragmentCompose.kt:1570-1585` | `qs_brightness_slider_position` (0 = сверху), `qs_show_brightness_slider` (по умолчанию 1) |
| Pulldown QS по одному пальцу (вкл/выкл) | `shade/QuickSettingsControllerImpl.java:430-433` | `STATUS_BAR_QUICK_QS_PULLDOWN` |
| Двойной тап для сна | `shade/QQSGestureListener.kt:47-54`, `shade/NotificationPanelViewController.java:803-805` | `DOUBLE_TAP_SLEEP_GESTURE` |
| AM/PM в часах | `statusbar/policy/Clock.java:363-365` | `STATUS_BAR_AM_PM` (по умолчанию AM_PM_STYLE_GONE) |
| Стиль и процент батареи | `statusbar/pipeline/battery/data/repository/BatteryRepository.kt:271-280` | `STATUS_BAR_BATTERY_STYLE`, `STATUS_BAR_SHOW_BATTERY_PERCENT` |
| Поворот экрана на экране блокировки | `shade/NotificationShadeWindowControllerImpl.java:310-312` | `LOCKSCREEN_ROTATION` |

- Ключи `LineageSettings` находятся в `upstream/lineage-sdk/sdk/src/java/lineageos/providers/LineageSettings.java`: строки 2735 (`QS_SHOW_AUTO_BRIGHTNESS`), 2729 (`QS_BRIGHTNESS_SLIDER_POSITION`), 1740/2721 (`QS_SHOW_BRIGHTNESS_SLIDER`).
- Lineage-ресурсы: `packages/SystemUI/res/values/lineage_config.xml` и `lineage_dimens.xml` не содержат параметров шторки (`lineage_dimens.xml` содержит только `global_actions_avatar_size = 24dp`).

---

## 7. Что подтверждено, что предположение (сводка по пункту 5)

**Подтверждено кодом:**
- Режим Dual требует `dual_shade && scene_container` (`DualShadeFlag.kt:42-43`, `SceneContainerFlag.kt:41-43`).
- Если Dual включён, по умолчанию Dual (`shade_config.xml:39`, `ShadeConfigRepository.kt:65-82`, `ShadeModeInteractor.kt:86-112`).
- Если Dual выключен, на телефоне Single (`ShadeModeInteractor.kt:158-166`, `config.xml:682`).
- Телефон full-width (`shade_config.xml:26`; w600dp переопределяет на false, `values-w600dp/shade_config.xml:19`).
- Lineage не переопределяет ни один из этих конфигов.

**Предположение (ПРЕД):**
- Значения флагов `dual_shade` и `scene_container` в релизной сборке Android 17 / LineageOS 24 (в клоне нет релизной конфигурации). Поэтому определить режим по умолчанию по коду нельзя.
- Альфа scrim в анимации перехода (`OverlayShade.kt:227-231`) и значение `2.57` как итог в пикселях.
- Смысл значения `qs_show_brightness_slider = 1` (показывать в QQS или в панели).
- Шаблоны даты (`abbrev_*`) — строк нет в клоне.
- Цвета `shade_panel_fg/bg/scrim` — нет в клоне, итоговые значения не известны.

---

## 8. Краткая таблица для порта на iOS (телефон, портрет, Dual или Single)

| Элемент | Значение |
|---|---|
| Отступ по бокам | 16dp |
| Высота status bar | 24dp |
| Часы (collapsed) | 14sp, шрифт variable-body-medium-emphasized, зона 48x48 |
| Часы (expanded) | ≈36sp (14 × 2.57), шапка min 120dp |
| Дата | 14sp / lineHeight 20, та же гарнитура |
| Chip статуса | капсула, padding 6dp/4dp, иконки 15dp, батарея 13sp × 7.8sp |
| Carrier | 14sp, letterSpacing 0.01em |
| Слайдер яркости | высота 40dp, thumb 4×52dp, скругление 12dp, иконка 28dp, auto-кнопка 52dp |
| Футер | кнопки 40dp, иконки 20dp, отступы 16dp, верх 8dp, низ 4dp |
| Тулбар (Dual) | 48dp, иконки 24dp, цветная подложка 36dp |
| Панель (Dual overlay) | 600dp max, радиус 46dp (только при не full-width), горизонтальный отступ 0 |
| Блюр | 23px, только при открытом bouncer |
| Scrim уведомлений | альфа 0.5 |
| Media | под плитками QQS (16dp), в QS-сцене после плиток, в Dual-overlay первым |
| Build number | слева, padding 16dp |

---

## 9. Файлы, которые читались

- `packages/SystemUI/compose/features/src/com/android/systemui/shade/ui/composable/`: `ShadeHeader.kt`, `ShadeScene.kt`, `OverlayShade.kt`, `ShadePanelScrim.kt`, `OverlayScrim.kt`, `ShadeHighlightChip.kt`, `VariableDayDate.kt`.
- `packages/SystemUI/compose/features/src/com/android/systemui/qs/ui/composable/`: `QuickSettingsContent.kt`, `QuickSettingsScene.kt`, `QuickSettingsShadeOverlay.kt`.
- `packages/SystemUI/compose/features/src/com/android/systemui/qs/footer/ui/compose/FooterActions.kt`.
- `packages/SystemUI/compose/features/src/com/android/systemui/notifications/ui/composable/NotificationsShadeOverlay.kt`.
- `packages/SystemUI/src/com/android/systemui/brightness/ui/compose/BrightnessSlider.kt`.
- `packages/SystemUI/src/com/android/systemui/shade/ui/ShadeColors.kt`, `shade/domain/interactor/ShadeModeInteractor.kt`, `shade/data/repository/ShadeConfigRepository.kt`, `shade/shared/flag/DualShadeFlag.kt`, `scene/shared/flag/SceneContainerFlag.kt`.
- `packages/SystemUI/src/com/android/systemui/qs/panels/ui/compose/toolbar/Toolbar.kt`, `qs/composefragment/QSFragmentCompose.kt`, `qs/footer/ui/viewmodel/FooterActionsButtonViewModel.kt`.
- Ресурсы: `packages/SystemUI/res/values/{dimens,shade_dimens,shade_config,config,colors,styles}.xml`, `values-night/colors.xml`, `values-w600dp/shade_config.xml`, `packages/SettingsLib/res/values/config.xml`, `core/res/res/values/{dimens,colors}.xml`.
- `aconfig/systemui.aconfig` (`dual_shade`, `scene_container`, `notification_shade_blur`).
- `upstream/lineage-sdk/sdk/src/java/lineageos/providers/LineageSettings.java` (ключи Lineage).

## Проверено по релизной конфигурации (platform/build/release, тег android-17.0.0_r1)

Android 17 — это релизы `cp1a`/`cp2a`; они наследуют значения от предыдущих (`bp1a`…`bp4a`). Если флага нет в release-конфигах, действует значение по умолчанию из aconfig — DISABLED.
- `scene_container` — ENABLED только в `trunk_staging`. В релизе Android 17 он **выключен**, значит Dual Shade тоже выключен. На телефоне классическая **одинарная шторка**: QQS сверху, под ней уведомления, второй свайп раскрывает полные QS.
- `qs_ui_refactor_compose_fragment` — ENABLED (bp3a): QS рисуются через Compose (`QSFragmentCompose`).
- `qs_compose_fragment_early_expansion` — ENABLED (bp4a).
- `notification_shade_blur` — ENABLED (bp3a): фон шторки размыт.
- `shade_header_font_update` — ENABLED (bp3a).
- `qs_edit_mode_v2` — ENABLED (cp1a): новый редактор плиток.
- `quick_settings_visual_haptics_longpress` — ENABLED (ap4a).
- `qs_new_tiles` — только trunk_staging: выключен.
