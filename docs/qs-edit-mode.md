# Редактор плиток Quick Settings (Edit Mode): спецификация для iOS-порта

Источник: `upstream/lineage-frameworks-base/packages/SystemUI/` (LineageOS 24.0, Android 17).
Все пути ниже относятся к этому корню. Сокращения: `qs/` = `src/com/android/systemui/qs/`, `panels/` = `qs/panels/`.

Метки: **[предположение]** значение выведено или взято из дефолтов Compose/Material, не из явного кода в дереве. Все прочие значения подтверждены ссылкой `файл:строка`.

---

## 0. Статус флага `qs_edit_mode_v2` и флаговые ветки

### 0.1 Флаг в дереве не найден

- Поиск по всему `upstream/` и по репозиторию: строк `qs_edit_mode_v2`, `qsEditModeV2`, `QsEditModeV2` нет ни в одном исходнике, aconfig или ресурсе.
- Объявленные в `aconfig/systemui.aconfig` флаги редактора QS: `qs_edit_mode_focus_fixes` (стр. 1332, bug 481033294), `qs_edit_mode_hover_fixes` (стр. 1342, bug 435626373), `qs_layout_mode` (стр. 1352, bug 485262315).
- Release-конфиг (`build/release`, где лежат значения флагов) в дереве отсутствует. Поэтому состояние `qs_edit_mode_v2` в Android 17 **не проверено**.
- Единственное упоминание включённого v2 есть в `/Users/makr/Documents/iPhone 8/LineageAOSP-iPhone8/journal/PROJECT.md:17` и `docs/qs-shade-layout.md:368`. Это утверждение из других заметок репозитория, не ссылка на исходник.

Следствие: в дереве нет ветки «legacy vs v2». Единственный редактор здесь - Compose-редактор (`infinitegrid/` + `selection/`). Ниже описан он. Различия внутри него задаются флагами из 0.2.

### 0.2 Флаговые ветки внутри редактора

| Флаг | Определение | Что меняет |
|---|---|---|
| `qs_edit_mode_focus_fixes` | `qs/flags/QsEditModeFocusFixes.kt:35`: `Flags.qsEditModeFocusFixes() && SceneContainerFlag.isEnabled` | Отступ focus-кольца декораций: `2dp` -> `-8dp` (`selection/Selection.kt:325-326`); `canFocus = false` у бейджа добавления (`Selection.kt:261-262`) |
| `qs_edit_mode_hover_fixes` | `qs/flags/QsEditModeHoverFixes.kt:35`: `Flags.qsEditModeHoverFixes() && SceneContainerFlag.isEnabled` | Декорация не композится при `NoDecoration` (`Selection.kt:152`); клик и ripple переезжают на `MinimumInteractiveSizeComponent` (`Selection.kt:189-191` vs `328-335`) |
| `qs_layout_mode` | `qs/flags/QsLayoutMode.kt:23-35` | Вкладки «Edit»/«Layout». Вызовов `QsLayoutMode.isEnabled` в `SystemUI` нет, в `DefaultEditTileGrid` вкладок нет. Вкладки `EditModeTabs` (`pods/qs/panels/ui/src/main/compose/infinitegrid/EditModeTabsImpl.kt`) зарегистрированы в Dagger (`pods/.../PanelsUIModule.kt:30`), но не вызываются |

Важно:
- Оба fix-флага требуют `SceneContainerFlag.isEnabled`.
- По `journal/PROJECT.md:17` scene_container на cp1a выключен. Значит на телефоне Android 17 fix-ветки **вероятно не активны**. **[предположение]** Ниже в разделах с размерами и взаимодействиями указано поведение без fix-флагов, если не сказано иное.
- Пункт «Settings» в overflow-меню тоже гейтится `SceneContainerFlag` (`panels/ui/viewmodel/EditTopBarActionsViewModel.kt:32`), поэтому обычно отсутствует.

---

## 1. Вход, переход и выход

### 1.1 Кнопка входа

- Кнопка находится в ряду тулбара футера QS, между переключателем пользователя и кнопкой «Настройки»: `panels/ui/compose/toolbar/Toolbar.kt:157-159` (`EditModeButton(editModeButtonViewModel, isVisible = isFullyVisible())`).
- Иконка: `com.android.systemui.common.ui.icons.Edit` (`toolbar/EditModeButton.kt:61`, `:160`).
- Контейнер: `IconButton`, `shape = RoundedCornerShape(CornerSize(28.dp))` (`toolbar/EditModeButton.kt:151`). Фокус-кольцо: `borderOnFocus`, цвет `secondary`, corner `24dp` (`:154-157`).
- Размер контейнера: в `EditModeButton` не задан, применяется дефолт `IconButton` Material 3 **[предположение]**: 40dp контейнер, иконка 24dp. Остальные кнопки тулбара используют `toolbar_button_size` 48dp, иконку 24dp (`res/values/shade_dimens.xml:74-75`, `Toolbar.kt:353-366`).
- Жеста long-press нет. Кнопка срабатывает по `onClick`: `toolbar/EditModeButton.kt:150`.
- Видимость: `EditModeButtonViewModel.isEditButtonVisible` скрывает кнопку только для headless-пользователя при `hsuQsChanges` (`panels/ui/viewmodel/toolbar/EditModeButtonViewModel.kt:70-74`).

Обработка тапа:
1. `EditModeButtonViewModel.onButtonClick()` (`EditModeButtonViewModel.kt:79-83`): проверка `falsingInteractor.isFalseTap(LOW_PENALTY)`, затем `activityStarter.postQSRunnableDismissingKeyguard { editModeViewModel.startEditing() }`.
2. `EditModeViewModel.startEditing()` (`panels/ui/viewmodel/EditModeViewModel.kt:168-173`): `_isEditing = true`, лог `QS_EDIT_OPEN` (`qs/QSEvents.kt:76`).
3. `QSFragmentCompose` (`composefragment/QSFragmentCompose.kt:357-364`) реагирует на `isEditing` через `synchronizeQsState` и запускает переход (1.2).

Тултип при первом показе:
- Текст: `qs_edit_mode_tooltip` = «Resize Quick Settings tiles» (`res/values/strings.xml:3130`).
- Задержка показа: `TOOLTIP_APPEARANCE_DELAY_MS = 2000L` (`EditModeButtonViewModel.kt:146`), показывается один раз: `onTooltipDisposed()` ставит `setEditTooltipShown(true)` (`EditModeButtonViewModel.kt:85-88`).
- Не показывается в test harness (`EditModeButtonViewModel.kt` `runningInTestHarness`).
- Стиль (`toolbar/EditModeButton.kt`): `PlainTooltip`, shape `RoundedCornerShape(16.dp)` (`:120`), контейнер `tertiary` (`:121`), текст `onTertiary` (`:122`), тень `2dp` (`:123`, `EditModeButtonDefaults.TooltipShadowElevation` стр. 314), `maxWidth = 360dp` (`:124`, стр. 313). Текст: `labelLarge`, `TextAlign.Center`, `maxLines = 2`, padding `horizontal 8dp / vertical 12dp` (`:139-145`). Треугольный caret `12dp x 8dp` (`:130`), направлен вниз, если помещается под якорем, иначе вверх (`:255-304`). Зазор до якоря `4dp` (`:312`).

### 1.2 Переход в режим редактирования

Редактор - отдельная сцена `SceneKeys.EditMode` внутри `SceneTransitionLayout` (`composefragment/QSFragmentCompose.kt:402-404`).

- Спецификация: `to(SceneKeys.EditMode) { spec = tween(durationMillis = EDIT_MODE_TIME_MILLIS); toEditMode() }` (`QSFragmentCompose.kt:336-339`), `EDIT_MODE_TIME_MILLIS = 500` (`QSFragmentCompose.kt:1177`).
- Кривая `tween` без явного easing: дефолт Compose `FastOutSlowInEasing` **[предположение]**.
- Фазы (`composefragment/ui/ToEditMode.kt:22-28`), прогресс перехода 0..1 за 500 мс:
  - QuickQuickSettings и QuickSettings: `fade` в диапазоне `0.0 ... 0.5` (исчезают, стр. 24-27).
  - EditMode: `fade` в диапазоне `0.5 ... 1.0` (появляется, стр. 23).
  - Итог: 0-250 мс старый контент гаснет, 250-500 мс редактор проявляется. Фейд линейный внутри подинтервала **[предположение]**. Сдвига или масштаба нет (в `TransitionBuilder` больше ничего не задано).
- Отступы содержимого сцены редактора (`QSFragmentCompose.kt:968-976`): горизонталь `QuickSettingsShade.Dimensions.HorizontalPadding` = `16dp` (`shade_dimens.xml:55`, `overlay_qs_layout_horizontal_padding`); сверху `padding(top = viewModel.qqsHeaderHeight)`.
- Синхронизация со скроллом шторки: `synchronizeQsState` (`QSFragmentCompose.kt:1096-1130`). При `editMode == true` вызывает `setTargetScene(EditMode)` и ждёт завершения.
- Во время редактирования слушатели плиток выключены (`QSFragmentCompose.kt:729`, `:862`) и QS не даёт скроллить (`:266-268`).
- При входе сбрасывается набор плиток: `editModeViewModel.tiles` перечитывается при переходе `isEditing: false -> true` (`panels/ui/viewmodel/EditModeViewModel.kt:103-107`, стр. 93-94 комментарий).

### 1.3 Выход из редактирования

Способы выхода (все ведут к `EditModeViewModel.stopEditing()`, `EditModeViewModel.kt:176-181`, лог `QS_EDIT_CLOSED`):
1. Стрелка «назад» в верхней панели: `EditModeTopBar.kt:118-139` (`NavigationArrow`), callback `onStopEditing` (`infinitegrid/EditTile.kt:298-299`).
2. Системная кнопка/жест назад: `BackHandler { viewModel.stopEditing() }` (`compose/EditMode.kt:33`).
3. Уход композабла из дерева: `DisposableEffect(Unit) { onDispose { viewModel.stopEditing() } }` (`compose/EditMode.kt:35`).
4. Закрытие шторки или QS не в полном развороте: `QSFragmentCompose.kt:367-381`.

Анимация выхода:
- Для обратного перехода `EditMode -> QuickSettings` в `QSFragmentCompose.kt` нет `from(EditMode)`. Поэтому используется дефолт библиотеки scene (`compose/scene/src/com/android/compose/animation/scene/SceneTransitions.kt:115-128`, `TransitionSpecImpl` без явного `spec`).
- Значение spec (тип пружины/длительность) в дереве **не найдено** **[предположение]**: в библиотеке дефолт вероятнее всего spring. Элементы без явного `fade` сдвигаются по сцене, а не гаснут. Для iOS-порта выход лучше сделать как зеркало входа (500 мс), это сохраняет симметрию.
- Синхронизация (`QSFragmentCompose.kt:1114-1116`): при выходе сцена переходит на `QuickSettings`, затем `snapTo` по прогрессу раскрытия (`:1117-1130`).

Прочее:
- Контроллер шторки (`setCustomizerShowing`) получает `EDIT_MODE_TIME_MILLIS` = 500 мс (`QSFragmentCompose.kt:665`).

---

## 2. Экран редактора (портрет)

### 2.1 Структура сверху вниз

`Scaffold` с прозрачным фоном (`infinitegrid/EditTile.kt:290-296`), внутри:

1. Верхняя панель `EditModeExpandableTopBar` (`infinitegrid/EditTile.kt:298-328`), `Modifier.statusBarsPadding()` (`:309`).
2. Прокручиваемая колонка (`EditTile.kt:343-371`, `EditModeScrollableColumn` стр. 378-412):
   - `Spacer(16.dp)` (`:351`);
   - текущие плитки `CurrentTilesGrid` (`:353-357`);
   - доступные плитки `AnimatedAvailableTilesGrid` (`:361-370`), включая кнопку «Reset» (`:730-743`).
3. `NavBarInsetScrollZone` (`:343`, `:415-431`): зона высотой nav-bar, перехватывает скролл без потребления, чтобы жест домой работал системно.

Колонка: `verticalArrangement = spacedBy(qs_label_container_margin)`, то есть `10dp` (`EditTile.kt:387-388`, `res/values/dimens.xml:726`). Верхний padding = высота `innerPadding` Scaffold (`:394`). Вертикальный скролл (`verticalScroll`, `:396`), снизу `Spacer` высотой `windowInsetsBottomHeight(systemBars)` (`:410`).

### 2.2 Верхняя панель

Компонент: `TwoRowsTopAppBar` (`infinitegrid/EditModeTopBar.kt:92-104`).
- Вертикальный padding `8dp` (`:102`), `windowInsets = WindowInsets(0.dp)` (`:103`).
- Прокрутка: `TopAppBarDefaults.enterAlwaysScrollBehavior()` (`EditTile.kt:284`, `:294`). Панель уезжает при скролле вниз и возвращается при скролле вверх.
- Цвета (`EditModeTopBar.kt:254-261`): контейнер и `scrolledContainer` = `Transparent`; заголовок и подзаголовок = `onSurface`.

Элементы:
- **Навигация:** `IconButton`, прозрачный, `onSurface`, иконка `ArrowBack` (автоматическое зеркало в RTL), `contentDescription` = `action_bar_up_description` (`EditModeTopBar.kt:118-139`). Размер иконки 24dp **[предположение]**, дефолт Material.
- **Заголовок:** «Edit tiles» (`qs_edit_tiles`, `res/values/strings.xml:3127`). Стиль `headlineMediumEmphasized`: 28sp, line-height 36sp, weight Medium (`compose/core/src/com/android/compose/theme/typography/TypographyTokens.kt:181-188`, `VariableFontTypeScaleEmphasizedTokens.kt:51-53`). `maxLines = 2`, `TextOverflow.Ellipsis` (`EditModeTopBar.kt:107-116`).
- **Подзаголовок** (показывается только когда панель развёрнута, `EditTile.kt:300-308`):
  - по умолчанию: «Select tiles to rearrange and resize» (`select_to_rearrange_tiles`, `strings.xml:3109`);
  - в режиме размещения: «Tap to position tile» (`tap_to_position_tile`, `strings.xml:3124`), выбор в `EditTile.kt:550-556`, состояние в `:511-535`.
  - Стиль `bodyMedium`: 14sp, line-height 20sp, weight Regular (`TypeScaleTokens.kt:28-31`).
- **Действия** (`EditTile.kt:312-327`): сначала Undo (условно), затем кнопка Remove. Дополнительные действия уходят в overflow.
  - Undo: `IconButton`, контейнер `surfaceEffect1`, иконка `Undo`, описание `com.android.internal.R.string.undo` (`EditTile.kt:265-282`). Появляется `fadeIn()` / `fadeOut()` (стр. 266). Виден только при `canUndo` (стек не пуст).
  - Remove: см. 2.6.
- **Overflow** `MoreVert` (`EditModeTopBar.kt:174-209`): показывается при двух и более действиях (`:146-150`). Описание `qs_edit_menu_content_description` = «Options» (`strings.xml:3136`).
  - `DropdownMenu`: контейнер `surfaceBright` (`:200`), shape `RoundedCornerShape(26.dp)` (`:198`), минимальная ширина `216dp` (`:199`).
  - Пункт: `DropdownMenuItem`, высота минимум `52dp` (`:236`), padding `16dp` (`:235`), иконка `20dp` (`:232`), текст `labelLarge` (`:224-229`). Цвет текста `onSurface`, иконка `onSurfaceVariant` (`:243-251`).
- Единственное возможное действие сейчас - «Settings» (`qs_edit_settings`, `strings.xml:3133`), его видно только при SceneContainer и dual-shade (см. 0.2).

### 2.3 Текущие плитки (сетка)

Сетка `LazyVerticalGrid` с фиксированным числом колонок (`EditTile.kt:618-645`, `:673-690`).

Параметры:
- Колонки: `quick_settings_infinite_grid_num_columns = 4` (`res/values/config.xml:68`), через `QSColumnsViewModel` (`InfiniteGridLayout.kt:153-154`, `:186`).
- Промежуток между плитками по горизонтали и вертикали: `TileArrangementPadding = 6.dp` (`CommonTile.kt:491`).
- Внутренний отступ сетки: `CurrentTilesGridPadding = 10.dp` (`EditTile.kt:1404`).
- `userScrollEnabled = false` (`EditTile.kt:686`), скроллит внешняя колонка.
- Рамка: `border(2.dp, primary, RoundedCornerShape(28.dp))` (`EditTile.kt:625-629`, `GridBackgroundCornerRadius = 28.dp` стр. 1406).
- Заливка: `drawRoundRect(primary, cornerRadius=28dp, alpha = 0.15f)` (`EditTile.kt:637-643`).
- Высота анимируется: `animateDpAsState(gridHeight(totalRows + 1, TileHeight, TileArrangementPadding, CurrentTilesGridPadding))` (`EditTile.kt:607-612`). `gridHeight = (72 + 6) * rows + 10 * 2` (`:832-834`). Формула даёт фактическую высоту плюс 6dp трейлинг-промежутка, если `row` 0-based **[предположение]**.

Размер плитки:
- Высота: `TileHeight = 72.dp` (`CommonTile.kt:477-480`, `res/values/shade_dimens.xml:39`).
- Ширина: одна колонка (`span = 1`) или `largeTilesSpan` колонок (`EditTile.kt:858-863`, `EditTileListState.kt:219-224`).
- Большая плитка: `largeTilesSpan = 2` по умолчанию (`panels/data/repository/LargeTileSpanRepository.kt:61`, `DEFAULT_LARGE_TILE_WIDTH = 2`). При fontScale >= 1.8 (`LargeTileSpanRepository.kt:60`) `largeSpan = columns / 2` или `columns` (`panels/ui/viewmodel/QSColumnsViewModel.kt:64-72`).
- Фон плитки: `tileBackground(cornerRadius = InactiveTileCornerRadius)` (`EditTile.kt:1083-1087`, `1361-1368`), `InactiveTileCornerRadius = 50.dp` (`CommonTile.kt:433-436`, `shade_dimens.xml:35-36`).
  - Скругление 50dp больше половины высоты (36dp). Compose обрезает радиус до половины меньшей стороны, поэтому фактически капсула, радиус ~36dp **[предположение]** (расчёт по правилам Compose).
- Цвет фона: `EditModeTileDefaults.editTileColors().background` = `LocalAndroidColorScheme.surfaceEffect1` (`EditTile.kt:1415-1417`).

Содержимое плитки (`EditTile.kt:1274-1351`, composable `EditTile`):
- Строка `Row`, промежуток `6.dp` (`:1285`), `largeTilePadding()` = `start 8dp`, `end 12dp` (`CommonTile.kt:377-382`, `StartPadding` = `shade_dimens.xml:38`, `TileEndPadding` = `CommonTile.kt:490`).
- Иконка: контейнер `ToggleTargetSize = 56.dp` (`CommonTile.kt:482-485`, `shade_dimens.xml:40`), иконка размером `SmallTileIconSize - (SmallTileIconSize - LargeTileIconSize) * progress` (`EditTile.kt:1338`): от `32dp` (`shade_dimens.xml:34`) до `28dp` (`shade_dimens.xml:37`).
- У dual-target плиток под иконкой круг `56dp` цвета `surfaceEffect2`, альфа = `progress` (`EditTile.kt:1329-1332`).
- Подписи (`LargeTileLabels`, `CommonTile.kt:203-225`): основная `titleSmallEmphasized` (14sp / 20sp, SemiBold), вторичная `labelMedium` (12sp / 16sp, Medium). Альфа подписей = `progress` (`EditTile.kt:1348`). Цвет `onSurface` (`:1419-1420`).
- Иконка без подписей (`progress = 0`) центрируется по `iconHorizontalCenter` (`EditTile.kt:1353-1359`).

Состояния плитки:
- Затемнение для `GreyedOut` (режим размещения): альфа контейнера `0.4` (`EditTile.kt:1036`, `Selection.kt:371-374`).
- Перемещаемая плитка подменяется пустым слотом: фон `secondary` с альфой `0.3` (`PLACEHOLDER_ALPHA`, `EditTile.kt:866-876`, `:1399`), скругление `InactiveTileCornerRadius`.

### 2.4 Доступные плитки

Видны, если не идёт перетаскивание Add и не включён режим размещения, либо активен Move (`EditTile.kt:367-370`).
- Скрываются через `AnimatedVisibility(fadeIn() / fadeOut())` (`EditTile.kt:709-712`). Длительность дефолтная Compose **[предположение]**.
- Контейнер: `requiredHeightIn(min = 200.dp)` (`EditTile.kt:1405`, `:704`) и `animateContentSize()` (`:704`).
- Внутренний промежуток колонки: `spacedBy(10.dp)` между сеткой и кнопкой Reset (`:717-718`).

Группы по категориям (`AvailableTileGrid`, `EditTile.kt:749-830`):
- Группировка: `groupAndSort(tiles)` (`EditTile.kt:759-761`). Порядок категорий по ordinal enum (`qs/shared/model/TileCategory.kt`):
  1. Connectivity, 2. Utilities, 3. Display, 4. Privacy, 5. Accessibility, 6. PROVIDED_BY_SYSTEM_APP, 7. PROVIDED_BY_APP, 8. Unknown.
  - Внутри группы плитки сортируются по имени (`TileCategory.kt`, `groupAndSort`, стр. 86-89).
- Промежуток между группами: `spacedBy(2.dp)` (`EditTile.kt:768`).
- Фон группы: `background(surface, alpha = 0.32f)` (`EditTile.kt:792-796`, `AVAILABLE_TILES_GRID_ALPHA = .32f` стр. 1402). Внутренний padding `16.dp` (`:797`).
- Скругления: первая группа - верхние углы 28dp, последняя - нижние 28dp, средние - прямоугольные (`EditTile.kt:775-788`).
- Заголовок категории (`CategoryHeader`, `EditTile.kt:1099-1117`):
  - `Row`, промежуток `8.dp` (`:1103`);
  - иконка: `painterResource(category.iconId)`, цвет `onSurface` (`:1106-1110`), размер по умолчанию **[предположение]** 24dp;
  - текст `titleMediumEmphasized` (16sp / 24sp, SemiBold), цвет `onSurface` (`:1111-1115`, `TypographyTokens.kt:205-212`).
  - Нижний отступ заголовка `16.dp` (`:799-802`).
  - Строки категорий (`res/values/strings.xml:4832-4862`): «Connectivity», «Accessibility», «Utilities», «Privacy», «From system apps», «From apps you installed», «Display», «Unknown».
- Строки плиток: `chunked(columns)` (`EditTile.kt:803`), промежуток `6.dp` (`:805`), высота строки `IntrinsicSize.Max` (`:806`). Недостающие места заполняются `Spacer` с `weight(1f)` (`:823`).

Ячейка доступной плитки (`AvailableTileGridCell`, `EditTile.kt:1119-1225`):
- Колонка, промежуток `CommonTileDefaults.StartPadding = 8.dp` (`:1144-1146`).
- Верхний блок: высота `TileHeight = 72.dp`, на всю ширину ячейки (`:1164`).
  - Фон: `tileBackground(InactiveTileCornerRadius)` = `surfaceEffect1` (`:1184`).
  - Иконка: `SmallTileContent` размером `32dp` (`CommonTile.kt:462-470`, `:1192-1197`), цвет `onSurface` (`:1415-1421`).
- Нижний блок: подпись `labelMedium` (12sp / 16sp, Medium, tracking 0.1sp) с `maxLines = 2`, `TextAlign.Center`, `Hyphens.Auto`, `TextOverflow.Ellipsis` (`:1213-1221`, `TypeScaleTokens.kt:72-76`). Для приложений: `AppIconText` с inline-иконкой `qs_edit_mode_app_icon = 14sp` (`:1228-1265`, `res/values/dimens.xml:738`).
- Если плитка уже в текущих (`cell.isCurrent`): вся ячейка с альфой `0.38` (`:1132`, `:1149`), нажатие и перетаскивание отключены (`:1186`, `:1166`).
- Бейдж «+»: `StaticTileBadge` (см. 3.5).
- Accessibility: подпись состояния «Tile already added» (`strings.xml:3183`) для текущих плиток.

### 2.5 Кнопка Reset

- `TextButton`, контейнер `primary`, текст `onPrimary` (`EditTile.kt:730-736`).
- Текст: `com.android.internal.R.string.reset` (`:740`), стиль `labelLarge` (`:741`). Текст берётся из framework, в дереве не виден.
- Отступ `vertical 16.dp` (`:737`).
- Нажатие: `EditAction.ResetGrid` (`:731`). Обработчик (`infinitegrid/InfiniteGridLayout.kt:212`, `:226-227`) вызывает `dialogDelegate.showDialog()`, снимок не создаётся (`:212`).

Диалог (`panels/ui/dialog/QSResetDialogDelegate.kt`):
- Заголовок: «Reset all tiles?» (`qs_edit_mode_reset_dialog_title`, `strings.xml:4864-4866`), строка 78.
- Текст: «All Quick Settings tiles will reset to the device’s original settings» (`qs_edit_mode_reset_dialog_content`, `strings.xml:4868-4870`), строка 80.
- Кнопки: `PlatformButton` «OK» (`android.R.string.ok`, стр. 83-90) и `PlatformTextButton` «Cancel» (стр. 94-95). OK: закрыть, вызвать `onReset()` и `resetInteractor.reset()` (стр. 84-88).
- `onReset` (`InfiniteGridLayout.kt:168-175`): очистка стека undo (`clearStack`, стр. 171), прокрутка наверх `scrollState.animateScrollTo(0)` (стр. 174).
- Сброс: `SizedTilesResetInteractor.reset()` (`panels/domain/interactor/SizedTilesResetInteractor.kt:37-39`): сбрасывает набор плиток и размеры (`currentTilesInteractor.resetTiles()`).

### 2.6 Кнопка Remove

- Composable `RemoveButton` (`EditTile.kt:559-598`).
- Форма: pill, `drawRoundRect(cornerRadius = height / 2)` (`:584-587`). Внутренний padding `10.dp` (`:590`).
- Текст: `qs_customize_remove` = «Remove» (`strings.xml:2432`), стиль `labelLarge` (`:595`).
- Включена: фон `primary`, текст `onPrimary` (`:568-569`, `:576`).
- Выключена: фон `onSurface` с альфой `0.1` (`:571`), текст `onSurface` с альфой `0.38` (`:577`).
- Переходы цвета: `updateTransition(enabled)` + `animateColor(transitionSpec = { tween() })` (`:565-578`), то есть дефолтный `tween()` = 300 мс с дефолтной кривой **[предположение]**.
- Включена, когда выбранная плитка удаляема: `selectionState.selection?.let { isTileRemovable(it) }` (`EditTile.kt:316`, `isTileRemovable` стр. 287-289 берёт `EditTileViewModel.isRemovable`, `panels/ui/viewmodel/EditTileViewModel.kt:110-111`).

### 2.7 Тайминг и раскладка на iPhone (предварительный расчёт)

Формулы выведены из кода, поэтому помечены **[предположение]**.

Для ширины экрана `W` (точки):
- Ширина колонки текущих плиток: `(W - 2*16 - 2*10 - 3*6) / 4`. Пояснение: 16 - отступ сцены, 10 - padding сетки, 6 - промежуток. Пример `W = 375`: `76.25`.
- Ширина большой плитки (span 2): `2 * colW + 6`. При `W = 375`: `158.5`.
- Ширина колонки доступных плиток: `(W - 2*16 - 2*16 - 3*6) / 4`. Пояснение: 16 - отступ сцены, 16 - padding группы. При `W = 375`: `73.25`.
- **Расхождение:** колонки текущих и доступных плиток отличаются на `3pt` при `W = 375` (`16+10` против `16+16` по краям). Это наблюдение из кода, не проверено на устройстве.
- Высота плитки: `72`. Промежуток между строками: `6`.

---

## 3. Взаимодействия

### 3.1 Выбор плитки (selection)

- Модель: `MutableSelectionState` (`selection/MutableSelectionState.kt:42-151`): одна выбранная плитка (`selection: TileSpec?`), флаг `placementEnabled`.
- Тап по текущей плитке: `selectableTile` с `detectEagerTapGestures` (`MutableSelectionState.kt:176-190`) -> `onTap(spec)`: если не в режиме размещения, то `select(spec)` (`:133-135`).
- Двойной тап по плитке (только вне режима размещения) включает режим размещения: `enterPlacementMode` (`:184-187`, `:75-78`).
- Автовыбор: если ничего не выбрано или выбранная плитка удалена, выбирается первая (`EditTile.kt:440-461`). Перед выбором пауза `AUTO_SELECT_DEBOUNCE_MILLIS = 100` мс (`EditTile.kt:1403`, `:457-459`). Во время drag автовыбор не работает (`:446`).
- При появлении новой плитки (`TileState.New`) выбор задерживается на `250 мс` (`MutableSelectionState.kt:105-112`). Смысл: не обрезать обводку и ручку.

Визуал выбранной плитки (`selection/Selection.kt`):
- Обводка внутри плитки: `2.dp`, цвет `primary`, скругление `InactiveTileCornerRadius` (`:138-144`, `:457-458` `SelectedBorderWidth`). Альфа обводки: 1 для `Selected` (`:500-512`), 0 для `New`/`None`/`GreyedOut` (`:448-455`).
- Ручка размера: pill `8dp x 16dp` (`:463-464`), цвет `primary` (`:505`), прижата к правому краю, смещение `-2dp` по X (`:509`), `zIndex` 2 у выбранной и 1 у остальных (`:342`).
- Ручка `Selected` подписана accessibility `toggle tile size`.
- Для режима размещения (`Placeable`): обводка `2dp primary` без ручки (`:516-526`).
- Фокус клавиатуры: `borderOnFocus(secondary, corner = InactiveTileCornerRadius)` (`EditTile.kt:1078-1081`), обводка 3dp и отступ 2dp (`qs/ui/compose/BorderOnFocus.kt:45-47`).

### 3.2 Изменение размера (resize)

- Ручка доступна только у выбранной плитки (`Selection.kt:134`, `:185`). Тянется по горизонтали через `anchoredDraggable(Horizontal)` (`:184-188`).
- Якоря (`selection/ResizingState.kt:89-103`):
  - `min` = ширина текущей плитки, если она уже иконка; иначе `(W - (span-1)*6) / span`.
  - `max` = `W * span + (span-1)*6`, если иконка; иначе `W`.
  - Якорь `Icon` = `min`, якорь `Large` = `max`. Начальный якорь из `startsAsIcon` (`ResizingState.kt:51-52`).
- Тап по ручке переключает размер: `toggleCurrentValue()` (`EditTile.kt:1011-1012`, `ResizingState.kt:109-112`), анимация `animateTo` с дефолтной spec **[предположение]** (`ResizingState.kt:105-107`).
- Промежуточное состояние (`TemporaryResizeOperation`) сразу перестраивает сетку (`EditTile.kt:654-656`, `EditTileListState.kt:114-124`).
- Фиксация (`FinalResizeOperation`) при settled-якоре (`ResizingState.kt:73-78`). Команда отправляется только если размер реально поменялся (`EditTile.kt:659-665`).
- Клавиатура: `R` переключает размер (`EditTile.kt:1388-1389`). Accessibility action `toggle tile size` (`:1062-1066`).
- Ширина тайла при ресайзе интерполируется через `anchoredDraggableState.offset` (`Selection.kt:341-351`).

### 3.3 Перетаскивание (drag and drop)

Жест: **long press** (`detectDragGesturesAfterLongPress`, `DragAndDropState.kt:197`). Начало drag на плитке доступно только если она выбрана или не в drag (`EditTile.kt:1020-1023`, `isSelectable = !dragInProgress`). Длительность long press - системная **[предположение]** (Android-дефолт `ViewConfiguration.getLongPressTimeout`, в дереве не проверено).

Типы (`DragAndDropState.kt:65-68`): `Move` (текущая плитка) и `Add` (из доступных).

**Перемещение (Move):**
- Старт: `dragType = Move`, плитка заменяется пустым слотом (`EditTile.kt:866-876`), `selectionState.select(spec)` (`:1031`).
- Изменение порядка «на лету»: `onTargeting(target, insertAfter)` перемещает плитку на индекс под пальцем (`EditTileListState.kt:135-155`, `regenerateGrid` стр. 227-232).
- `insertAfter`: если цель - большая плитка и палец правее её центра, вставка после неё (`DragAndDropState.kt:178-183`).
- Цель определяется по `visibleItemsInfo` (`DragAndDropState.kt:142-149`).
- Выход за границы текущей сетки: если плитка удаляема, она пропадает из списка сразу (`EditTileListState.kt:161-171`, `DragAndDropState.kt:131-134`).
- Drop на сетке: `SetTiles(...)` и выбор перетащенной плитки (`EditTile.kt:630-633`), `onDrop` очищает состояние (`EditTileListState.kt:173-180`).

**Добавление (Add):**
- Старт из доступной плитки (`EditTile.kt:1165-1176`): `dragType = Add`, ширина элемента 1 колонка (`SizedTileImpl(cell, 1)`, стр. 1170).
- Доступные плитки скрываются (fade out) на время drag (`EditTile.kt:367-370`). При старте Add колонка скроллится наверх (`EditTile.kt:336-340`).
- Вставка на лету: временная `TileGridCell(draggedTile, 0, 0)` (`EditTileListState.kt:149-151`), затем перерасчёт строк.
- Drop - тот же `SetTiles`.
- Выход за границы: `isDraggedCellRemovable = true` для Add (`EditTileListState.kt:53-56`), плитка удаляется из списка (`:161-171`).

**Удаление перетаскиванием:**
- Зона удаления: вся прокручиваемая колонка, `dragAndDropRemoveZone` (`EditTile.kt:397-406`, `DragAndDropState.kt:78-104`).
- Если сработал drop в зоне и `removalEnabled` (плитка удаляема), вызывается `RemoveTile`. Иначе - `SetTiles` с текущим порядком (`EditTile.kt:398-405`).

**Режим тапа (альтернатива перетаскиванию):**
- Двойной тап по плитке (или клавиша `M`) - режим размещения (см. 3.4).

Haptics: в коде редактора вызовов haptic нет (`EditTile.kt`, `Selection.kt`, `DragAndDropState.kt`, `EditTileListState.kt` - пусто). Тактильный отклик в QS-плитках (`TileHapticsViewModel`, `infinitegrid/Tile.kt:173-175`) относится к обычному режиму. В `CommonTile.kt:157` haptic отключён явно. Значит в редакторе haptic = системный drag/drop (если есть) **[предположение]**.

Автоскролл при перетаскивании (`EditTile.kt:465-509`):
- Зона `AUTO_SCROLL_DISTANCE = 100` (пиксели, `EditTile.kt:1400`) от верхнего и нижнего края видимой области.
- Скорость: `AUTO_SCROLL_SPEED = 2` мс на пиксель, `tween(distance * 2, LinearEasing)` (`:501-506`). То есть линейная скорость 0.5 пикселя/мс.

### 3.4 Режим размещения (placement)

- Вход: двойной тап по плитке (`MutableSelectionState.kt:184-187`), либо клавиша `M` (`EditTile.kt:1384-1386`), либо accessibility action `toggle placement mode` (`EditTile.kt:1046-1050`).
- Выбранная плитка: `Placeable` (обводка 2dp primary, без ручки). Остальные: `GreyedOut` (альфа 0.4) (`MutableSelectionState.kt:101-104`).
- Доступные плитки скрыты (`EditTile.kt:367-370`).
- Место назначения: тап по плитке (`PlaceToTileSpec`, `MutableSelectionState.kt:89-94`) или по пустому слоту (`SpacerGridCell` с `pointerInput`, `EditTile.kt:890-895`, `PlaceToIndex`, `:145-150`).
- Преобразование индекса сетки в индекс списка: `targetIndexForPlacement` (`EditTileListState.kt:188-217`).
- Повторный тап по выбранной плитке отменяет режим (`MutableSelectionState.kt:127-129`).
- Размещение отправляет `InsertTile(spec, index)` (`EditTile.kt:256-263`), обработчик `addTile(..., position)` (`InfiniteGridLayout.kt:219-221`).
- Заголовок-подзаголовок меняется на «Tap to position tile» (см. 2.2).

### 3.5 Добавление плитки

- Тап по доступной плитке или по бейджу «+» (`EditTile.kt:1134-1139`): `onAddTile(spec)` -> добавление **в конец** (`EditTile.kt:726`, `InfiniteGridLayout.kt:216-218` передаёт `listState.tileSpecs().size`; `EditModeViewModel.addTile` стр. 187-217, `POSITION_AT_END`), затем `selectionState.select(spec)` (`:1137`).
- Бейдж «+»: `StaticTileBadge(icon = Icons.Default.Add, enabled = !isCurrent)` (`EditTile.kt:1200-1205`).
  - Размер круга `24dp` (`Selection.kt:459`, `BadgeSize`), цвет `primary` (`:270`, `:277`), иконка `onPrimary` размером `16sp` (`:274`, `BadgeIconSize = 16.sp`, стр. 460).
  - Смещение: `x = -4dp`, `y = +4dp` от правого верхнего угла, угол `-0.8 rad` (`:461-462`, `:258`).
  - Альфа `1` если доступно, `0` если уже добавлена (`:256`).
  - Зона касания: `LocalMinimumInteractiveComponentSize` (`:297`, дефолт Compose 48dp **[предположение]**), ripple радиуса `12dp` (`:266`).
- Уже добавленная плитка: тап не действует (`clickable(enabled = !isCurrent)`, `EditTile.kt:1186`), бейдж неактивен (`:1203`).

### 3.6 Удаление плитки

Три пути:
1. **Кнопка Remove** в верхней панели (`EditTile.kt:315-326`): удаляет выбранную плитку. Перед удалением выбирает соседнюю (следующую, а если последняя - предыдущую): `findNeighboringTile` (`EditTileListState.kt:94-107`), затем `RemoveTile` (`EditTile.kt:318-325`). Включена только если плитка `isRemovable` (см. 2.6).
2. **Перетаскивание наружу** (см. 3.3): удаляемая плитка пропадает при выходе за границы текущей сетки и удаляется при drop в зоне.
3. **Бейдж «-» (`Removable`)**: в текущем коде **недостижим**. `TileGridCell` передаёт `canShowRemovalBadge = false` (`EditTile.kt:909`), состояние `Removable` не назначается (`MutableSelectionState.kt:115`). Визуал бейджа (`Selection.kt:484-496`, фон `primaryContainer`, иконка `Remove` 16sp `onPrimaryContainer`) в дереве есть, но не используется.

Минимум плиток:
- `quick_settings_min_num_tiles = 6` (`res/values/config.xml:106`), через `MinimumTilesInteractor`.
- Удаление разрешено, если `currentSpecs.size > minNumberOfTiles` (`panels/ui/viewmodel/EditModeViewModel.kt:123`). Иначе действия `REMOVE` нет (`:135-139`), кнопка Remove выключена, перетаскивание наружу не удаляет (`EditTileListState.kt:53-56`).

### 3.7 Undo

- Стек снимков: `InfiniteGridSnapshotViewModel` (`panels/ui/viewmodel/InfiniteGridSnapshotViewModel.kt`), максимум `SNAPSHOTS_MAX_SIZE = 10` (стр. 79), старые удаляются (стр. 62-63).
- Снимок делается перед каждым действием, кроме `ResetGrid` (`InfiniteGridLayout.kt:212-214`).
- `canUndo = snapshots.isNotEmpty()` (`InfiniteGridSnapshotViewModel.kt:45`).
- Кнопка появляется и исчезает через fade (см. 2.2). Сброс стека - при Reset (`InfiniteGridLayout.kt:171`).

### 3.8 Скролл и прокрутка

- Внешняя колонка скроллится вертикально (`EditTile.kt:396`). Сетка текущих плиток не скроллится сама (`:686`).
- Верхняя панель: `enterAlwaysScrollBehavior` (`:284`, `:294`).
- При drag Add скролл наверх (`:336-340`). При Reset скролл наверх (`InfiniteGridLayout.kt:174`).
- Автоскролл при drag: см. 3.3.

---

## 4. Цвета, радиусы, размеры, текст

### 4.1 Цвета (Material roles и альфы)

Значения M3-ролей (`primary`, `onSurface` и т.д.) задаются динамической схемой системы. Конкретных hex в дереве нет. Ниже только роли.

| Элемент | Роль | Альфа | Источник |
|---|---|---|---|
| Фон экрана редактора | прозрачный (Scaffold `containerColor`) | 0 | `EditTile.kt:296` |
| Верхняя панель, контейнер | прозрачный | 0 | `EditModeTopBar.kt:256-257` |
| Заголовок, подзаголовок, иконка назад | `onSurface` | 1 | `EditModeTopBar.kt:130`, `:258-259` |
| Рамка текущей сетки | `primary` | 1 (2dp) | `EditTile.kt:625-627` |
| Заливка текущей сетки | `primary` | 0.15 | `EditTile.kt:637-643` |
| Фон текущей плитки | `surfaceEffect1` (system) | 1 (0.4 при GreyedOut) | `EditTile.kt:1417`, `:1036` |
| Фон иконки dual-target | `surfaceEffect2` (system) | `progress` | `EditTile.kt:1418`, `:1331` |
| Иконка и подписи плитки | `onSurface` | 1 | `EditTile.kt:1419-1421` |
| Вторичная подпись | `onSurface` | 1 | `EditTile.kt:1420` |
| Обводка выбранной плитки | `primary` | 1 (2dp) | `Selection.kt:139`, `:458` |
| Ручка размера | `primary` | 1 | `Selection.kt:505` |
| Пустой слот перемещения | `secondary` | 0.3 | `EditTile.kt:871-872`, `:1399` |
| Фокус-кольцо | `secondary` | 1 (3dp, отступ 2dp) | `EditTile.kt:1079`, `BorderOnFocus.kt:45-47` |
| Фон группы доступных | `surface` | 0.32 | `EditTile.kt:793-795`, `:1402` |
| Ячейка уже добавленной плитки | (вся ячейка) | 0.38 | `EditTile.kt:1132` |
| Заголовок категории и иконка | `onSurface` | 1 | `EditTile.kt:1109`, `:1114` |
| Бейдж «+» | круг `primary`, иконка `onPrimary` | 1 | `Selection.kt:270-277` |
| Бейдж «-» (недостижим) | круг `primaryContainer`, иконка `onPrimaryContainer` | 1 | `Selection.kt:489-490`, `:204` |
| Кнопка Remove, включена | фон `primary`, текст `onPrimary` | 1 | `EditTile.kt:568-576` |
| Кнопка Remove, выключена | фон `onSurface`, текст `onSurface` | 0.1 / 0.38 | `EditTile.kt:571`, `:577` |
| Кнопка Reset | фон `primary`, текст `onPrimary` | 1 | `EditTile.kt:734-735` |
| Кнопка Undo | фон `surfaceEffect1`, иконка `onSurface` | 1 | `EditTile.kt:272-273` |
| Overflow-меню, фон | `surfaceBright` | 1 | `EditModeTopBar.kt:200` |
| Пункт меню, текст | `onSurface` | 1 | `EditModeTopBar.kt:245` |
| Пункт меню, иконка | `onSurfaceVariant` | 1 | `EditModeTopBar.kt:246` |
| Тултип, фон | `tertiary` | 1 | `toolbar/EditModeButton.kt:121` |
| Тултип, текст | `onTertiary` | 1 | `toolbar/EditModeButton.kt:122` |
| Кнопка Edit в футере | `onSurface` (LocalContentColor) | 1 | `toolbar/EditModeButton.kt:81`, `:160` |

Значения `surfaceEffect1/2` (`compose/core/src/com/android/compose/theme/AndroidColorScheme.kt:132-133` -> `customColorSurfaceEffect1/2`, маппинг в `core/res/res/values/colors_dynamic.xml:182-183` и `values-night/colors_dynamic.xml:182-183` -> `system_surface_effect_*` в `core/res/res/values/colors.xml`):

| Токен | Светлая | Тёмная |
|---|---|---|
| `surfaceEffect1` | `#FAF8FE` (`core/res/res/values/colors.xml:858`) | `#121317` (`core/res/res/values/colors.xml:912`) |
| `surfaceEffect2` | `#FFFFFF` (`core/res/res/values/colors.xml:860`) | `#D9E2FF` (`core/res/res/values/colors.xml:914`) |

**[предположение]** Значение `surfaceEffect2` в тёмной теме (`#D9E2FF`) светло-голубое. Это прямой вывод из дерева, но визуально выглядит неожиданно. Перепроверить на устройстве.

### 4.2 Радиусы скругления

| Элемент | Радиус | Источник |
|---|---|---|
| Плитка (текущая и доступная) | 50dp, фактически капсула ~36dp | `CommonTile.kt:433-436`, `shade_dimens.xml:35-36` |
| Текущая сетка (рамка и заливка) | 28dp | `EditTile.kt:1406`, `:625-628` |
| Группа доступных (первая/последняя) | 28dp | `EditTile.kt:775-788` |
| Ручка размера | 8dp x 16dp, радиус = ширина/2 | `Selection.kt:463-464`, `:506` |
| Бейдж | круг | `Selection.kt:277` |
| Кнопка Remove | pill (высота/2) | `EditTile.kt:586` |
| Кнопка Edit (футер) | 28dp; фокус 24dp | `toolbar/EditModeButton.kt:151`, `:156` |
| Тултип | 16dp | `toolbar/EditModeButton.kt:120` |
| Overflow-меню | 26dp | `EditModeTopBar.kt:198` |
| Фокус-кольцо декораций | 50% | `Selection.kt:323` (`CornerSize(50)`) |

### 4.3 Размеры и отступы (сводка)

| Параметр | Значение | Источник |
|---|---|---|
| Боковой отступ сцены редактора | 16dp | `shade_dimens.xml:55` |
| Отступ сверху | высота QQS-хедера | `QSFragmentCompose.kt:977-982` |
| Промежуток колонки | 10dp | `dimens.xml:726` |
| Spacer сверху | 16dp | `EditTile.kt:351` |
| Padding сетки текущих | 10dp | `EditTile.kt:1404` |
| Промежуток плиток | 6dp | `CommonTile.kt:491` |
| Высота плитки | 72dp | `shade_dimens.xml:39` |
| Внутренний отступ группы | 16dp | `EditTile.kt:797` |
| Отступ заголовка группы снизу | 16dp | `EditTile.kt:801` |
| Промежуток между группами | 2dp | `EditTile.kt:768` |
| Промежуток заголовок/иконка | 8dp | `EditTile.kt:1103` |
| Промежуток иконка/подпись (доступные) | 8dp | `EditTile.kt:1146` |
| Минимальная высота доступных | 200dp | `EditTile.kt:1405` |
| Padding кнопки Reset | 16dp vertical | `EditTile.kt:737` |
| Padding кнопки Remove | 10dp | `EditTile.kt:590` |
| Иконка плитки (большая/малая) | 28dp / 32dp | `shade_dimens.xml:34`, `:37` |
| Контейнер иконки (dual-target) | 56dp | `shade_dimens.xml:40` |
| Иконка категории | дефолт 24dp **[предположение]** | `EditTile.kt:1106-1110` |
| Иконка бейджа | 16sp | `Selection.kt:460` |
| Иконка приложения в подписи | 14sp | `dimens.xml:738` |
| Иконка меню | 20dp | `EditModeTopBar.kt:232` |
| Padding пункта меню | 16dp, min высота 52dp | `EditModeTopBar.kt:235-236` |
| Ширина меню | min 216dp | `EditModeTopBar.kt:199` |
| Размер бейджа | 24dp | `Selection.kt:459` |
| Смещение бейджа | x -4dp, y +4dp | `Selection.kt:461-462` |
| Тултип: отступ, max-ширина, тень | 4dp, 360dp, 2dp | `toolbar/EditModeButton.kt:312-314` |
| Тултип: padding текста | 8dp / 12dp | `toolbar/EditModeButton.kt:144` |
| Caret тултипа | 12dp x 8dp | `toolbar/EditModeButton.kt:130` |
| Кнопка тулбара | 48dp контейнер, 24dp иконка | `res/values/shade_dimens.xml:74-75` |
| Ширина обводки выбора | 2dp | `Selection.kt:458` |
| Ширина фокус-кольца | 3dp, отступ 2dp | `BorderOnFocus.kt:45-47` |

### 4.4 Текстовые стили

| Элемент | Стиль | Размер / line-height | Вес | Источник |
|---|---|---|---|---|
| Заголовок «Edit tiles» | `headlineMediumEmphasized` | 28sp / 36sp | Medium | `TypographyTokens.kt:181-188`, `VariableFontTypeScaleEmphasizedTokens.kt:51-53` |
| Подзаголовок | `bodyMedium` | 14sp / 20sp | Regular | `TypeScaleTokens.kt:28-31` |
| Название категории | `titleMediumEmphasized` | 16sp / 24sp | SemiBold | `TypographyTokens.kt:205-212`, `VariableFontTypeScaleEmphasizedTokens.kt:75-77` |
| Подпись плитки (большая, основная) | `titleSmallEmphasized` | 14sp / 20sp | SemiBold | `CommonTile.kt:217`, `TypographyTokens.kt:213-220` |
| Подпись (вторичная, приложение) и подпись доступной плитки | `labelMedium` | 12sp / 16sp, tracking 0.1sp | Medium | `CommonTile.kt:225`, `EditTile.kt:1219`, `TypeScaleTokens.kt:72-76` |
| Текст кнопок Remove и Reset, пункты меню, тултип | `labelLarge` | 14sp / 20sp | Medium | `EditTile.kt:595`, `:741`, `EditModeTopBar.kt:226`, `toolbar/EditModeButton.kt:141`, `TypeScaleTokens.kt:68-71` |

Ограничения строк:
- Подпись доступной плитки: `maxLines = 2`, `Ellipsis`, `Hyphens.Auto` (`EditTile.kt:1215-1220`).
- Заголовок панели: `maxLines = 2` (`EditModeTopBar.kt:113-114`).
- Тултип: `maxLines = 2` (`toolbar/EditModeButton.kt:143`).

Шрифт: `typeScaleTokens.bodyMediumFont` и т.д. (`TypeScaleTokens.kt`) задают семейства. В основной тип-шкале используется `typefaceTokens.plain` (`TypeScaleTokens.kt:72`).

---

## 5. Анимации и тайминги (сводка)

| Что | Длительность / параметры | Кривая | Источник |
|---|---|---|---|
| Переход QS -> редактор | 500 мс | `tween` (дефолт Compose) | `QSFragmentCompose.kt:336-339`, `:1177` |
| Фейд QQS/QS (уход) | 0 - 250 мс (фракция 0..0.5) | линейная внутри фазы **[предположение]** | `composefragment/ui/ToEditMode.kt:24-27` |
| Фейд редактора (появление) | 250 - 500 мс (фракция 0.5..1) | линейная внутри фазы **[предположение]** | `composefragment/ui/ToEditMode.kt:23` |
| Обратный переход редактор -> QS | дефолт библиотеки scene **[предположение]** | не найдено | `compose/scene/.../SceneTransitions.kt:115-128` |
| Тултип: задержка показа | 2000 мс | - | `EditModeButtonViewModel.kt:146` |
| Цвет кнопки Remove | 300 мс (`tween()` дефолт) **[предположение]** | `FastOutSlowIn` дефолт **[предположение]** | `EditTile.kt:567`, `:575` |
| Высота текущей сетки | `animateDpAsState`, дефолтная пружина **[предположение]** | spring | `EditTile.kt:607-612` |
| Размещение плиток (move/insert) | `spring(stiffness = StiffnessMediumLow, dampingRatio = DampingRatioLowBouncy, visibilityThreshold = IntOffset.VisibilityThreshold)` | пружина: stiffness 400, damping ratio 0.75 | `EditTile.kt:1407-1412`, применяется `:1006` (`animateItem(placementSpec)`) |
| Снятие `placementSpec` во время ресайза | - | - | `EditTile.kt:994` |
| Фейд доступных (скрытие при drag Add) | дефолт `fadeIn()/fadeOut()` **[предположение]** | - | `EditTile.kt:709-712` |
| Изменение размеров доступной секции | `animateContentSize()` дефолт | spring **[предположение]** | `EditTile.kt:704` |
| Альфа серой (GreyedOut) | `animateFloatAsState`, дефолт | spring **[предположение]** | `EditTile.kt:1036` |
| Альфа добавленной плитки | `animateFloatAsState`, дефолт | spring **[предположение]** | `EditTile.kt:1132` |
| Декорации выбора (цвет, размер, смещение, альфа) | `updateTransition` + `animate*`, дефолт | spring **[предположение]** | `Selection.kt:125-133` |
| Угол декорации | `Animatable.animateTo` дефолт | spring **[предположение]** | `Selection.kt:384-397` |
| Цвет декорации | `Animatable.animateTo` дефолт | spring **[предположение]** | `Selection.kt:406-419` |
| Ресайз (анкор) | `AnchoredDraggableState.animateTo` дефолт | spring **[предположение]** | `ResizingState.kt:105-107` |
| Подзаголовок (смена текста) | `AnimatedContent` дефолт | fade + slide **[предположение]** | `EditTile.kt:545-556` |
| Появление Undo | `fadeIn()` / `fadeOut()` дефолт | - | `EditTile.kt:266` |
| Автоскролл при drag | 2 мс на пиксель, линейно | `LinearEasing` | `EditTile.kt:1401`, `:501-506` |
| Автовыбор (задержка) | 100 мс | - | `EditTile.kt:1403`, `:459` |
| Задержка выбора новой плитки | 250 мс | - | `MutableSelectionState.kt:111` |
| Текстовый отзыв тулбара (не редактор) | `fadeIn(tween(200))` / `fadeOut(tween(200))` | `tween(200)` | `toolbar/Toolbar.kt:330-331` |

Дефолтные значения Compose (**[предположение]**, в дереве не проверены):
- `tween()` = 300 мс, `FastOutSlowInEasing`.
- `spring()` = `dampingRatio = 1.0`, `stiffness = 1500`.

Для iOS-порта пружину `StiffnessMediumLow = 400, DampingRatioLowBouncy = 0.75` можно переписать в `UISpringTimingParameters` с `mass = 1`, `stiffness = 400`, `damping = 2 * 0.75 * sqrt(400) = 30`.

---

## 6. Строки (ключи и значения)

| Ключ | Текст | Строка в `res/values/strings.xml` |
|---|---|---|
| `qs_edit_tiles` | Edit tiles | 3127 |
| `select_to_rearrange_tiles` | Select tiles to rearrange and resize | 3109 |
| `tap_to_position_tile` | Tap to position tile | 3124 |
| `qs_edit_mode_tooltip` | Resize Quick Settings tiles | 3130 |
| `qs_edit_settings` | Settings | 3133 |
| `qs_edit_menu_content_description` | Options | 3136 |
| `qs_customize_remove` | Remove | 2432 |
| `qs_edit_edit_tab` | Edit | 3118 (вкладка, не используется) |
| `qs_edit_layout_tab` | Layout | 3121 (вкладка, не используется) |
| `resize_and_reorder_tiles` | Resize and reorder layout | 3115 (не используется) |
| `tap_to_remove_tiles` | Tap to remove tiles | 3112 (не используется) |
| `qs_edit_mode_category_connectivity` | Connectivity | 4832-4834 |
| `qs_edit_mode_category_accessibility` | Accessibility | 4836-4838 |
| `qs_edit_mode_category_utilities` | Utilities | 4840-4842 |
| `qs_edit_mode_category_privacy` | Privacy | 4844-4846 |
| `qs_edit_mode_category_providedBySystemApps` | From system apps | 4848-4850 |
| `qs_edit_mode_category_providedByApps` | From apps you installed | 4852-4854 |
| `qs_edit_mode_category_display` | Display | 4856-4858 |
| `qs_edit_mode_category_unknown` | Unknown | 4860-4862 |
| `qs_edit_mode_reset_dialog_title` | Reset all tiles? | 4864-4866 |
| `qs_edit_mode_reset_dialog_content` | All Quick Settings tiles will reset to the device’s original settings | 4868-4870 |
| `accessibility_qs_edit_toggle_tile_size_action` | toggle the tile's size | 3162 |
| `accessibility_qs_edit_remove_tile_action` | Remove tile | 3165 |
| `accessibility_qs_edit_place_tile_action` | Place tile | 3168 |
| `accessibility_qs_edit_toggle_placement_mode` | toggle placement mode | 3171 |
| `accessibility_qs_edit_toggle_selection` | toggle selection | 3174 |
| `accessibility_qs_edit_named_tile_add_action` | Add %1$s to the last position | 3177 |
| `accessibility_qs_edit_position` | Position %1$d | 3180 |
| `accessibility_qs_edit_tile_already_added` | Tile already added | 3183 |
| `accessibility_qs_edit_tile_added` | Tile added | 3186 |
| `accessibility_qs_edit_tile_removed` | Tile removed | 3189 |

Примечания:
- `qs_edit_edit_tab` и `qs_edit_layout_tab` объявлены, но в экране Android 17 без `QsLayoutMode` не выводятся.
- Строки `undo`, `reset`, `ok`, `cancel`, `action_bar_up_description` берутся из framework (`com.android.internal.R` / `android.R`) и в дереве SystemUI не объявлены. Значения **[предположение]**: «Undo», «Reset», «OK», «Cancel», «Navigate up».
- Строки категорий и подписей: `CHAR LIMIT=NONE`, перенос допускается.

---

## 7. Ограничения, крайние случаи, наблюдения

1. Минимум плиток: 6 (см. 3.6). Ниже 6 действие Remove недоступно.
2. Выбор всегда есть, если плитки есть: автовыбор первой (3.1).
3. Удаление выбранной плитки переносит выбор на соседнюю (3.6).
4. Во время drag Add доступные плитки скрыты, поэтому нельзя добавить ещё одну плитку, пока держим первую.
5. Во время размещения недоступны: drag, resize, и доступные плитки скрыты (`EditTile.kt:367-370`).
6. Выход из редактора автоматически при закрытии шторки или сворачивании QS (2.5, `QSFragmentCompose.kt:367-381`).
7. Для RTL: `ArrowBack` зеркалится автоматически (`EditModeTopBar.kt:134`), `insertAfter` содержит TODO про RTL (`DragAndDropState.kt:180`), LazyGrid RTL-баг `b/412357793` (`EditTile.kt:990-993`).
8. Наблюдение: колонки текущих и доступных плиток различаются на 3pt (см. 2.7). Возможно, это задумано, возможно, нет. Не проверено на устройстве.
9. Наблюдение: `gridHeight(totalRows + 1, ...)` добавляет трейлинг-промежуток (см. 2.3). **[предположение]** о назначении - ряд для drop в новую строку.
10. Наблюдение: `surfaceEffect2` в тёмной теме = `#D9E2FF` (см. 4.1). Нестандартно, проверить.

---

## 8. Предположения и пробелы (полный список)

1. Состояние флага `qs_edit_mode_v2` в Android 17 не подтверждено (раздел 0.1). Описан единственный Compose-редактор.
2. Состояние `SceneContainerFlag` на телефоне не подтверждено. От него зависит поведение focus/hover fixes (0.2). Раздел 2-3 описывает поведение **без** fix-флагов, если не сказано иное.
3. Значения дефолтных spring/tween Compose (раздел 5) не проверены в дереве.
4. Обратная анимация EditMode -> QS: spec не найдена (1.3).
5. Размер иконки категории 24dp, иконки Edit и кнопки Navigate up: дефолты Material **[предположение]**.
6. Тексты `undo`, `reset`, `ok`, `cancel`, `action_bar_up_description` из framework (2.5, раздел 6).
7. Система drag (визуал перетаскиваемой плитки, тактильность): в коде не описана **[предположение]**.
8. Длительность long press: системная (Android `ViewConfiguration`), **[предположение]** около 400 мс.
9. Кривые `FastOutSlowInEasing`, `LinearEasing` и `tween()` дефолтов - **[предположение]**.
10. Расчёты геометрии (раздел 2.7) выведены из кода и не сверены с устройством.

---

## 9. Для iOS-порта (краткие соответствия)

- Long press -> drag: `UILongPressGestureRecognizer` (минимум 0.4 с) + `UIDragInteraction` или собственный жест. Интерактивный drop меняет порядок на лету, как в `EditTileListState.onTargeting`.
- Двойной тап -> режим размещения: `UITapGestureRecognizer(numberOfTapsRequired: 2)`.
- Ручка размера: `UIPanGestureRecognizer` с двумя якорями (Icon/Large), по окончании `UIViewPropertyAnimator` или пружина `(400, 30, 1)`.
- Переход QS -> редактор: 500 мс, `UIViewPropertyAnimator` с кривой, близкой к `FastOutSlowIn` (`cubic-bezier(0.4, 0, 0.2, 1)`). Фейд: 0-0.5 для старого, 0.5-1 для нового.
- Accessibility: перенести `customActions` (3.1-3.6) через `accessibilityCustomActions`.
- Цвета: токены `surfaceEffect1/2` в светлой и тёмной теме (4.1). M3-роли взять из текущей палитры iOS-приложения.
