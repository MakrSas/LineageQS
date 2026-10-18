# Motion шторки Android 17 (LineageOS 24): QQS -> QS, fling, scrim

Цель: воспроизвести на iOS движение шторки Android 17: тянем сверху -> видна шторка с QQS (первая строка плиток); тянем дальше или второй свайп -> полный QS.

Документ составлен только чтением исходников. Ничего не менялось. Все числа взяты из кода (file:line). Всё, что выведено логически или не проверяется в дереве, помечено **предположение**.

## 0. Соглашения и карта файлов

Сокращения (пути от корня `upstream/`):

| Сокр. | Файл |
|---|---|
| `QSC` | `lineage-frameworks-base/packages/SystemUI/src/com/android/systemui/shade/QuickSettingsControllerImpl.java` |
| `NPVC` | `.../SystemUI/src/com/android/systemui/shade/NotificationPanelViewController.java` |
| `SVC` | `.../SystemUI/src/com/android/systemui/shade/ShadeViewController.kt` |
| `SEM` | `.../SystemUI/src/com/android/systemui/shade/ShadeExpansionStateManager.kt` |
| `SHC` | `.../SystemUI/src/com/android/systemui/shade/ShadeHeaderController.kt` |
| `QSFC` | `.../SystemUI/src/com/android/systemui/qs/composefragment/QSFragmentCompose.kt` |
| `QSVM` | `.../SystemUI/src/com/android/systemui/qs/composefragment/viewmodel/QSFragmentComposeViewModel.kt` |
| `QSFT` | `.../SystemUI/src/com/android/systemui/qs/composefragment/ui/FromQuickQuickSettingsToQuickSettings.kt` |
| `SQUISH` | `.../SystemUI/src/com/android/systemui/qs/panels/ui/compose/infinitegrid/SquishTile.kt` |
| `SCRIM` | `.../SystemUI/src/com/android/systemui/statusbar/phone/ScrimController.java` |
| `SSA` | `.../SystemUI/src/com/android/systemui/statusbar/notification/stack/StackScrollAlgorithm.java` |
| `SIA` | `.../SystemUI/animation/src/com/android/systemui/animation/ShadeInterpolation.kt` |
| `INTERP` | `upstream/aosp-libs-systemui/animationlib/src/com/android/app/animation/Interpolators.java` |
| `VECS` | `upstream/aosp-libs-systemui/mechanics/src/com/android/mechanics/behavior/VerticalExpandContainerSpec.kt` |
| `CSCENE` | `.../SystemUI/compose/scene/src/com/android/compose/animation/scene/` (DraggableHandler, SwipeDetector, SwipeAnimation, SceneTransitionLayout) |
| `CFEAT` | `.../SystemUI/compose/features/src/com/android/systemui/scene/ui/composable/transitions/` |
| `SUA` | `.../SystemUI/src/com/android/systemui/shade/ui/viewmodel/ShadeUserActions.kt` |

`.../SystemUI/` = `upstream/lineage-frameworks-base/packages/SystemUI/`.

### 0.1. Две реализации шторки в дереве

В дереве есть два пути, выбираемые флагом `scene_container` (`.../SystemUI/aconfig/systemui.aconfig:1470`, `SceneContainerFlag.kt` через `Flags.sceneContainer()`):

1. **Legacy (View)**: `NPVC` (высота панели, touch), `QSC` (QS-высота, QQS<->QS, clip, scrim), `QSFC` (Compose-содержимое QS внутри ComposeView), `SCRIM`, `SHC`. Здесь почти везде стоит `SceneContainerFlag.assertInLegacyMode()` (например `NotificationStackScrollLayoutController.java:1378`).
2. **Scene container (Compose)**: `Shade`/`QuickSettings`-сцены, переходы в `CFEAT`, жесты в `CSCENE`, маппинг жестов в `SUA`.

Значение `scene_container` по умолчанию в этом дереве не видно: флаги заданы в release-конфиге вне дерева. **Предположение**: переносить стоит оба подхода по принципу, но кривые/пороги одинаковы или очень близки; порядок величин (кроме переходов Compose) совпадает.

`QSFC` (Compose) является контентом QS в обоих путях; его внутренний STL "QQS <-> QS" управляется прогрессом `qsExpansion` из `QSC` (раздел 2).

---

## 1. Единый параметр: прогресс раскрытия

### 1.1 Legacy: две величины

- **Высота панели** `H = NPVC.mExpandedHeight`; доля панели `f_panel = H / Hmax_panel`, где `Hmax_panel = getMaxPanelTransitionDistance()` (`NPVC:2164-2183`). Для обычной шторки это `getMaxPanelHeight()` (`NPVC:1846`), а при QS-режиме `calculatePanelHeightExpanded` (`QSC:1500`).
- **Высота QS** `mExpansionHeight` (`QSC:880`, clamp между `getMinExpansionHeight()` и `getMaxExpansionHeight()`). Минимум = высота QQS (`QSFC:437-442` -> `viewModel.qqsHeight`), максимум = `mQs.getDesiredHeight()` (полная высота QS, `QSC:913-921`).
- **QS-доля** `q = computeExpansionFraction()`: `(mExpansionHeight - mMinExpansionHeight) / (mMaxExpansionHeight - mMinExpansionHeight)`, clamp в [0,1] (`QSC:1186-1195`).

### 1.2 Как панель переводит QS (важно для порта)

- Пока QS закрыт (`getExpanded() == false`), QS-высота (`mExpansionHeight`) остаётся на минимуме (QQS), поэтому `q` = 0 независимо от `H`. Тянем шторку -> меняется только `H` (`QSC:1186`, `QSC:880`). Это и есть фаза "только QQS".
- Переход в QS при тяге вниз внутри уже раскрытого QS (`goingBetweenClosedShadeAndExpandedQs`, `QSC:675-682`):
  `q_target = (H - panelHeightQsCollapsed) / (panelHeightQsExpanded - panelHeightQsCollapsed)`, где `panelHeightQsCollapsed = intrinsicPadding + layoutMinHeight`, `panelHeightQsExpanded = calculatePanelHeightExpanded(...)` (`NPVC:1906-1931`). Потом `setExpansionHeight(min + q*(max-min))` (`NPVC:1927-1930`).
- Переход в QS вручную: касание QS-области -> `QSC.onTouch` (`QSC:1792`) в `ACTION_MOVE` ставит `setExpansionHeight(h + mInitialHeightOnTouch)` (`QSC:1830-1832`), где `h = y - mInitialTouchY`. Значит QS тянется пальцем 1:1, без задержки.

### 1.3 Compose (QSFC / QSVM)

- Входные значения из `QSC`: `setQsExpansion(qsExpansionFraction, panelExpansionFraction, headerTranslation, squishinessFraction)` (`QSFC:520-529`) -> поля `qsExpansion`, `panelExpansionFraction`, `squishinessFraction`, `proposedTranslation` (`QSVM:163-165`, `QSFC:524-529`).
- `expansionState.progress` (`QSVM:236-260`) = `qsExpansion` с нижним порогом `EARLY_EXPANSION = 1e-6` (`QSVM:622`) когда `isQsExpanded && panelExpansionFraction >= 1 && squishinessFraction >= 1`. Иначе 0. `isStackScrollerOverscrolling` -> 0.
- Idle-сцена по прогрессу: `progress < 0.5 -> QuickQuickSettings`, иначе `QuickSettings` (`QSFC:1080-1085`). В переходе прогресс подаётся напрямую в `ExpansionTransition.progress` (`QSFC:1096-1139`, `ExpansionTransition` `QSFC:1141-1170`).
- Прогресс `0` -> `snapTo(QuickQuickSettings)`, `1` -> `snapTo(QuickSettings)` (`QSFC:1118-1126`).

---

## 2. Стадии раскрытия и привязка к визуалу

Ниже стадии по `H` (legacy) и `q` (QS). Для Compose тот же смысл через `expansionState.progress`.

### Стадия A: закрыто, `H = 0`

Видна только строка статуса: QS клипуется до нулевой высоты (`QSC:1241-1268`).

### Стадия B: тянем шторку, видим QQS (`q = 0`, `H` растёт)

Визуал:

1. **Squish стека уведомлений**: `updateExpansion` (`QSC:1094-1101`) берёт `squishiness = notificationSquishinessFraction`, если QS не раскрыт и панель не полностью раскрыта. Это значение (`SSA:598-616`): `stackHeight / stackEndHeight` минус шелф и scrim-паддинг. То есть доля видимой высоты стека от полной высоты. Стек визуально сжимается, а QQS сжимается вместе с ним.
2. **Squish QQS-плиток** (Compose): `constrainSquishiness(x) = clamp(0.1 + 0.9*x, 0, 1)` (`QSVM:628-630`), то есть squish никогда не уходит ниже 0.1. Плитка масштабирует высоту `expectedHeight * squishValue` и центрируется сдвигом `scroll = (squishedHeight - expectedHeight)/2` (`SQUISH:35-58`, формула `SQUISH:51-54`). Измерение через `approachLayout` (`SQUISH:37`, `QSFC:712`).
3. **Параллакс заголовка/QS**: `getHeaderTranslation()` (`QSC:771-790`): в состоянии `SHADE` переход `startHeight = -H * QS_PARALLAX_AMOUNT`, где `QS_PARALLAX_AMOUNT = 0.175` (`NPVC:243`), далее `lerp(startHeight, 0, appearAmount)`, но не выше 0. В Compose это `headerTranslation` (`QSVM:450-451`) = `proposedTranslation` (или 0 при `isTransitioningToFullShade`).
4. **Клип QS**: `setClippingBounds()` (`QSC:1241-1268`) и `calculateTopClippingBound` (`QSC:1542-1577`): верхняя граница клипа = `notificationTop` (edge позиция стека) + `overStretch`. QS "выезжает" из под неё. Для QS-клипа также есть translation `(top - headerHeight) * 0.175` (`QSC:1349-1350`).

Scrim в этой стадии: см. раздел 5.

### Стадия C: QQS -> QS (`q` от 0 до 1)

Визуал:

1. **Высота QS**: `mExpansionHeight` растёт от `min` (QQS) к `max` (полный QS) (`QSC:880-899`). В Compose `qsExpansion` тянет `expansionState` и `viewModel.heightOverride` (`QSFC:472`).
2. **Squish -> 1** (QS раскрыт): `QSC:1094-1097`: `if ((isExpandImmediate() || getExpanded()) && !mSplitShadeEnabled) squishiness = 1`. То есть при раскрытии QQS-плитки перестают сжиматься.
3. **Альфа контента QS**: `viewAlpha` (`QSVM:290-300`): `isSmallScreen -> ShadeInterpolation.getContentAlpha(alphaProgress)`, иначе `largeScreenShadeInterpolator.getQsAlpha(...)`. `alphaProgress = panelExpansionFraction` (`QSVM:453-462`). `getContentAlpha(x) = easeInOut(clamp((x - 0.3) / 0.7, 0, 1))` (`SIA:24-27`).
4. **Вертикальный сдвиг QS**: `viewTranslationY = headerTranslation` (`QSVM:272-282`) (при overscroll - `overScrollAmount`).
5. **Row reveal (Compose)**: `QuickSettingsContent` (бриджинг, яркость, плитки) проявляется на `fractionRange(start = 0.43f, end = 1 - SHARED_TILE_PICKER_THRESHOLD)`, где `SHARED_TILE_PICKER_THRESHOLD = 0.05` (`QuickSettings.kt:62`; `CFEAT/FromShadeToQuickSettingsTransition.kt:37-38`). Футер: `fractionRange(start = 0.9f)` (`QSFT:29`) либо `timestampRange(endMillis = 83)` для шторки (`FromShadeToQuickSettingsTransition.kt:35`). QQS-плитки `fade(QqsTileElementMatcher)` в `fractionRange(end = 0.5f)` (`QSFT:40`, `FromShadeToQuickSettingsTransition.kt:49`). Сами плитки шарятся между QQS и QS через `sharedElement(TileElementMatcher, enabled = animateTilesExpansion)` (`QSFT:33`, `QSVM:340-341`).
6. **Header morph (legacy)**: `SHC.qsExpandedFraction` (`SHC:232-238`) -> `header.progress = qsExpandedFraction` (`SHC:621-626`), то есть MotionLayout-прогресс между стартовым и конечным состоянием шапки. Альфа шапки от `shadeExpandedFraction`: `header.alpha = getContentAlpha(value)` (`SHC:222-226`). Иконки оператора выключаются при `qsExpandedFraction >= 0.5` (`SHC:645-652`).
   Compose-вариант: `CFEAT/FromShadeToQuickSettingsTransition.kt:62-69`: свёрнутый заголовок исчезает на `[0, 0.14]`, развёрнутый контент и оператор появляются с `0.58`. Перенос заголовка: `translate(CollapsedContentStart, y = CollapsedHeightForTransitions)` и т.п. (`CFEAT/FromShadeToQuickSettingsTransition.kt:52-61`).

### Стадия D: полный QS (`q = 1`)

- `mFullyExpanded = height == maxHeight` (`QSC:887`). `onExpansionHeightSetToMax` (`NPVC:3456`) обновляет высоту панели до максимума (`updateExpandedHeightToMaxHeight`, `NPVC:3088-3107`).
- При открытии с overshoot: `NPVC:1441-1447`, см. раздел 3.

---

## 3. Fling и settle

### 3.1 Пороги касания и жестов (legacy)

| Параметр | Значение | Где |
|---|---|---|
| `mTouchSlop` | `ViewConfiguration.getScaledTouchSlop()` | `NPVC:999`, `QSC:465` |
| `mSlopMultiplier` (неоднозначный жест) | `getScaledAmbiguousGestureMultiplier()` | `NPVC:1000`, `QSC:466`; используется при `CLASSIFICATION_AMBIGUOUS_GESTURE` (`NPVC:2838-2843`, `QSC:1907-1913`) |
| Значения TouchSlop/Multiplier | платформенные, в дереве не найдены | **предположение**: брать системные значения iOS-аналога (порядка 8-10 pt) |
| Порог falsing для QS | `qs_falsing_threshold = 60dp` | `.../SystemUI/res/values/dimens.xml:858`, `QSC:472` |
| Порог falsing для панели | `NPVC.getFalsingThreshold() = QSC.falsingThreshold * f`, `f = 1.5` если пробуждение тапом/жестом, иначе `1.0` | `NPVC:1704-1707`, `SVC:112-113` |
| Falsing "касание достаточно далеко" | `h >= falsingThreshold` -> `mTouchAboveFalsingThreshold = true` | `QSC:1833-1835`, `NPVC:4260` (`-h >= getFalsingThreshold()`) |

Порог начала тяги (QS-перехват в `onIntercept`, `QSC:1907-1925`): старт, если `h > touchSlop` (или `h < -touchSlop` при раскрытом QS) **и** `|h| > |dx|` **и** `shouldQuickSettingsIntercept(...)`. Для NPVC аналогично (`NPVC:3950-3968`, `h < -touchSlop` или `hAbs > touchSlop` при `openShadeWithoutHun`/`mAnimatingOnDown`).

### 3.2 Решение "раскрыть или свернуть" (legacy)

- Скорость: `VelocityTracker.computeCurrentVelocity(1000)` -> px/s (`NPVC:2941`, `QSC:1619-1624`).
- Если `|vectorVel| < minVelocity` (берётся из `FlingAnimationUtils`), то раскрыть только при `fraction > 0.5` (`NPVC:1588-1594`, `flingExpandsQs`; `NPVC:1669-1693`, `flingExpands`). Иначе - знак скорости: раскрывать при `vel > 0`.
- `shouldExpandWhenNotFlinging()` (`NPVC:1596-1607`): раскрыть при `expandedFraction > 0.5`; для касаний, пришедших с лаунчера (`mAllowExpandForSmallExpansion`), ещё и если прошло <= 300 мс с DOWN (`MAX_TIME_TO_OPEN_WHEN_FLINGING_FROM_LAUNCHER = 300`, `NPVC:257`).
- Если QS уже анимируется, панель остаётся раскрытой (`NPVC:1686-1688`, `mQsController.isExpansionAnimating()`).
- QS-вариант при отпускании: `QSC.flingQsWithCurrentVelocity` (`QSC:2083-2105`): `expandsQs = NPVC.flingExpandsQs(vel)`; при ложном касании (`isQsFalseTouch`) `expandsQs = false`; тип: `FLING_EXPAND` или `FLING_COLLAPSE` (в split - `FLING_HIDE`).

### 3.3 Физика и длительности (legacy)

Аниматоры: `ValueAnimator` + `FlingAnimationUtils.apply(animator, from, to, vel, height)` (из платформы, см. 7). Параметры конструктора (`NPVC:715-731`) и `loadDimens` (`NPVC:997-1004`, вызывается из `onFinishInflate` `NPVC:909-910`):

| Тип | maxLengthSeconds | speedUpFactor | прочее | где |
|---|---|---|---|---|
| Открытие (`mFlingAnimationUtils`) | **0.4 s** (после `loadDimens`; конструктор ставит 0.6, `FLING_MAX_LENGTH_SECONDS`) | 0.6 (только в конструкторе) | - | `NPVC:715-718`, `NPVC:1003-1004` |
| Закрытие (`mFlingAnimationUtilsClosing`) | 0.6 | 0.6 | - | `NPVC:720-723` |
| "Dismiss" (`mFlingAnimationUtilsDismissing`) | 0.5 | 0.6 | `setX2(0.6)`, `setY2(0.84)` | `NPVC:725-730` |

Значения `FLING_*` - `SVC:117-120`.

**Открытие панели** (`NPVC.flingToHeight`, `NPVC:1417-1483`):
- Overshoot, только если `expand && state != KEYGUARD && mOverExpansion == 0 && vel >= 0` (`NPVC:1432-1436`).
- Амплитуда: `overshoot = lerp(0.2, 1.0, saturate(vel / (highVelocity * 0.5)))` (`NPVC:1441-1447`, `FACTOR_OF_HIGH_VELOCITY_FOR_MAX_OVERSHOOT = 0.5` `NPVC:252`); смещение = `overshoot * 16dp` (`panel_overshoot_amount`, `NPVC:1002`, `values/dimens.xml:899`).
- Длительность при `vel == 0`: `SHADE_OPEN_SPRING_OUT_DURATION = 350 ms` (`NPVC:245`, `NPVC:1457-1460`).
- Возврат overshoot: `springBack()` длительность `SHADE_OPEN_SPRING_BACK_DURATION = 400 ms` (`NPVC:246`), интерполятор `FAST_OUT_SLOW_IN` (`NPVC:3052-3068`).

**Закрытие панели** (`NPVC:1459-1485`):
- Если `shouldUseDismissingAnimation()` (`NPVC:2158`):
  - `vel == 0`: интерполятор `PANEL_CLOSE_ACCELERATED` (`INTERP:186-187`), длительность `200 + (H / viewH) * 100` мс (`NPVC:1465-1467`);
  - иначе `mFlingAnimationUtilsDismissing` (`NPVC:1469`).
- Иначе `mFlingAnimationUtilsClosing` (`NPVC:1473`).
- Если `vel == 0`, длительность делится на `collapseSpeedUpFactor` (`NPVC:1478-1480`). Для `collapse()` (`NPVC:1316-1338`) factor = 1, для `mFlingCollapseRunnable` (`NPVC:571`) задан отдельно.

**QS-анимации** (`QSC:1994-2050`, `flingQs`):
- Цели: `FLING_EXPAND -> getMaxExpansionHeight()`, `FLING_COLLAPSE -> getMinExpansionHeight()` (QQS), `FLING_HIDE -> 0` (`QSC:1994-2015`).
- Клик (`isClick`): `TOUCH_RESPONSE` (`INTERP:198-199` = `PathInterpolator(0.3, 0, 0.1, 1)`), длительность **368 мс** (`QSC:2034-2035`).
- Смена направления (`vel` противоположен цели): сбрасывается `vel = 0`, длительность **350 мс** (`QSC:2026-2044`).
- Иначе: `mFlingQsWithoutClickListener.onFlingQsWithoutClick(...)`, которое в NPVC вызывает `mFlingAnimationUtils.apply(...)` (`NPVC:787`, `NPVC:3451-3453`), то есть та же кривая, что и у панели (0.4 s).
- Размер QS при смене max-высоты: `startSizeChangeAnimation` 300 мс, `FAST_OUT_SLOW_IN` (`QSC:951-972`, `QSC:957-958`).
- Клип-анимация: `FAST_OUT_SLOW_IN` с `mNotificationBoundsAnimationDuration` (`QSC:1290-1291`).

**Интерполяторы** (`INTERP`):
- `FAST_OUT_SLOW_IN = LEGACY = PathInterpolator(0.4, 0, 0.2, 1)` (`INTERP:126`, `INTERP:152`).
- `EMPHASIZED` (`INTERP:46`, кривая `INTERP:320-326`): `(0,0) -> cubic -> (1,1)`; аналог "fast_out_extra_slow_in".
- `TOUCH_RESPONSE = (0.3, 0, 0.1, 1)` (`INTERP:198-199`).
- `PANEL_CLOSE_ACCELERATED = (0.3, 0, 0.5, 1)` (`INTERP:186-187`).

### 3.4 Пружины (Compose)

- Жест: `DraggableHandler`/`SwipeAnimation`. Порог скорости **125 dp/s** (`CSCENE/SwipeDetector.kt:44`, `SwipeDetectorDefaults.VelocityThreshold`); позиционный порог **56 dp** (`CSCENE/DraggableHandler.kt:59-60`, `CSCENE/SwipeAnimation.kt:229`).
- Решение о коммите (`DraggableHandler.kt:414-460`, `shouldCommitSwipe`):
  - при свайпе вниз: коммит если `velocity >= velocityThreshold`, или `offset >= positionalThreshold && !wasCommitted`, или цель ближе; нет коммита если `offset < 0` или скорость обратная порогу;
  - аналогично для свайпа вверх.
- Анимация доводки: `layoutState.motionScheme.slowSpatialSpec()` по умолчанию (`CSCENE/SwipeAnimation.kt:465`); fling/decay: `decayAnimationSpec` (`SwipeAnimation.kt:56, 121, 135`). Конкретные значения `MotionScheme` в дереве не найдены (это материал3, см. раздел 7).
- Шторка как "контейнер раскрытия" (`VECS`): `VisibleHeight = 24 dp` (`VECS:146`), `PreDetachRatio = 0.25` (`VECS:147`), `DetachHeight = 80 dp` (`VECS:148`), `AttachHeight = 40 dp` (`VECS:149`); пружины `AttachSpring = DetachSpring = {stiffness 380, damping 0.9}` (`VECS:156-157`); `OpacitySpring = {1200, 0.99}` (`VECS:158`). Высота задаётся `createHeightSpec` (`VECS:53-90`): вниз до `detachHeight` на `preDetachRatio` `fractionalInputFromCurrent`, далее identity с `detachSpring`; вверх - `attachSpring` (`VECS:61-86`).
- Для шторки в Compose тип: `rememberShadeExpansionMotion(isFullWidth)` -> `VerticalExpandContainerSpec(isFloating = !isFullWidth, radius)` (`compose/features/.../shade/ui/composable/OverlayShade.kt:262-266`).

### 3.5 Длительности переходов (Compose, scene)

| Переход | Длительность | Где |
|---|---|---|
| Shade -> QS (свайп вниз с шапки) | 500 мс | `CFEAT/FromShadeToQuickSettingsTransition.kt:96` |
| QS -> Shade (обратно) | та же функция `reversed` | `FromShadeToQuickSettingsTransition.kt:73-80` |
| Gone -> QS (через 0.9 масштаб) | 500 * 0.9 мс | `SceneContainerTransitions.kt:172` |
| ToQuickSettingsShade (оверлей) | 300 мс | `CFEAT/ToQuickSettingsShadeTransition.kt:49` |
| ToNotificationsShade | 300 мс | `CFEAT/ToNotificationsShadeTransition.kt:64` |
| ToSingleShade | 500 мс | `CFEAT/ToSingleShadeTransition.kt:77` |
| Смена QQS<->QS внутри `QSFC` | `from(QQS, QS)` без явного spec (по умолчанию STL) | `QSFC:333-335` |
| Редактирование QS | `tween(500)` | `QSFC:336-338`, `QSFC:1177` |

---

## 4. Что открывает QS напрямую

### 4.1 Legacy

1. **Два пальца от статус-бара**: `isOpenQsEvent` (`QSC:616-650`): `ACTION_POINTER_DOWN && pointerCount == 2` (`QSC:621-622`). Требует `mTwoFingerExpandPossible` (ставится на DOWN, когда шторка полностью свернута и expansion разрешён, `QSC:1746-1747`) и `isInStatusBar` (`event.getY < mStatusBarMinHeight`, `QSC:1694`). Далее `setExpandImmediate(true)` (`QSC:1749-1751`), то есть QS раскрывается сразу целиком, без промежуточной QQS-фазы.
   Также `isOpenQsEvent` возвращает true для стилуса с кнопкой (`QSC:624-626`) и мыши (`QSC:628-631`).
2. **Однопальцевое вытягивание с края** (настройка Lineage `STATUS_BAR_QUICK_QS_PULLDOWN`): `QSC:430-434` (чтение), `QSC:636-650`. Значения: `1` = правый край, `2` = левый край; ширина зоны `w/4` (`QSC:619`, `float region = w * 1.f / 4.f`). Работает только в состоянии `StatusBarState.SHADE` (`QSC:650`). **Lineage-специфично**, в AOSP такого нет.
3. **Тяга за QS-заголовок (QQS)**: `shouldQuickSettingsIntercept` (`QSC:733-770`). При свёрнутом QS перехват только если касание попало в прямоугольник заголовка (`onHeader`, `QSC:756-768`). Если QS раскрыт, перехват ещё и при `yDiff < 0` внутри QS-области (`QSC:768`, `isTouchInQsArea` `QSC:601-614`).
4. **Касание QQS при свёрнутой панели**: `canPanelCollapseOnQQS` (`QSC:801-811`): сворачивание возможно, если касание было в шапке/QQS.

### 4.2 Compose (scene container)

`SUA` (`ShadeUserActions.kt`):
- Одиночная шторка (`singleShadeActions`, строки 41-52; параметр `requireTwoPointersForTopEdgeForQs`, по умолчанию `false`, `SUA:36-37`):
  - `Swipe.Down` (без края) и `Swipe.Down(pointerCount = 2)` -> `Shade` (`SUA:41-42`);
  - `swipeDownFromTopEdge()` (1 палец от верхнего края) -> `QuickSettings` (`SUA:45-50`), если `requireTwoPointersForTopEdgeForQs = false`; иначе -> `Shade`;
  - `swipeDownFromTopEdge(pointerCount = 2)` -> `QuickSettings` (`SUA:52`).
- Двойная шторка (`dualShadeActions`, `SUA:73-89`): `Swipe.Down` со стилусом/пальцем (кроме мыши) -> уведомления (`SUA:78`); `Swipe.Down` из правой половины верхнего края -> QS (`SUA:79-81`); два пальца -> QS (`SUA:85`).
- Сцена шторки в `ShadeUserActionsViewModel.kt:75` (`set(Swipe.Down, QuickSettings)`): `Swipe.Down -> QuickSettings` (вариант, когда режим одиночный).
- Split-шторка (`SUA:62-66`): тянуть вниз -> шторка; из края или двумя пальцами -> тоже шторка/QS по набору.

---

## 5. Scrim и видимость фона при раскрытии

### 5.1 Формулы

`SIA:13-16`: `getNotificationScrimAlpha(f) = easeInOut(clamp(f / 0.5, 0, 1))`.
`SIA:24-27`: `getContentAlpha(f) = easeInOut(clamp((f - 0.3) / 0.7, 0, 1))`.
`SIA` (`interpolateEaseInOut`): `m = f*1.2 - 0.2`; если `m <= 0` то 0; иначе `o = 1 - m`, результат `1 - 0.5*(1 - cos(pi * o*o))`, где `pi = 3.14159`.

То есть scrim в первые ~17% прогресса практически 0, а к 100% достигает 0.5 от непрозрачного (с кривой ease-in-out).

### 5.2 Legacy: `SCRIM`

- Входы: `setQsPosition(qsExpansionFraction, qsPanelBottomY)` (`SCRIM:931-937`) -> `expansionFraction = getNotificationScrimAlpha(qsFraction)`, `mQsExpansion` = этот результат. Вызывается из `QSC.updateExpansion` (`QSC:1119`).
- Альфы в `SHADE`-подобных состояниях:
  - если `mClipsQsScrim` (`SCRIM:970-982`; в режимах `notificationShadeBlur()` или `bouncerUiRevamp()` **всегда false**, `SCRIM:973-976`): `notifAlpha = (interp)^0.8 * defaultAlpha`, `behindAlpha = 1` (`SCRIM:1068-1072`);
  - иначе `behind = state.getBehindAlpha() * panelFraction`, `notif = state.getNotifAlpha() * panelFraction` (`SCRIM:1077-1080`) в blur-режиме; или `LargeScreenShadeInterpolator` (`SCRIM:1082-1088`) в обычном;
  - для `KEYGUARD/SHADE_LOCKED`: `notifAlpha = max(1 - interpolated, mQsExpansion)` (`SCRIM:1149`).
- `getInterpolatedFraction()` (`SCRIM:1379-1385`) = `getNotificationScrimAlpha(panelFraction)` (или bouncer-версия).
- Scrim кликабелен, если альфа > 0 (`SCRIM:1387-1392`). Обработчик "тап по scrim = свернуть" в legacy не найден в дереве; в Compose это `onScrimClicked` -> `collapseQuickSettingsShade` (`QuickSettingsShadeOverlayContentViewModel.kt:220-222`) и `collapseNotificationsShade` (`NotificationsShadeOverlayContentViewModel.kt:202-204`). **Предположение**: в legacy тап по scrim сворачивает через `NotificationShadeWindowViewController` (не проверено).
- Для большого экрана в портрете: `LargeScreenPortraitShadeInterpolator.kt:30-36` (behind `0..0.3`, notif `0.3..0.75`). На телефоне не используется.

### 5.3 Compose

- Оверлей QS (`ToQuickSettingsShadeTransition.kt:42-43`): scrim `fade` на `[0, 0.5]`; заголовок и статус-бар на `[0.5, 1]`.
- Переход в уведомления (`ToNotificationsShadeTransition.kt:59-61`): статус-бар на `[0.16, 0.8]`, placeholder стека `[0.33, 0.8]`, scrim `[0, 0.5]`.

---

## 6. Стек уведомлений во время раскрытия (высокий уровень)

- `QSC.updateExpansion` передаёт в NSSL `setQsExpansionFraction(q)` (`QSC:1128-1131`), при split - 0.
- Во время жеста NSSL получает `setPanelFlinging(true/false)` (`NPVC:1423`, `NPVC:1541`).
- Squish стека = `stackHeight / stackEndHeight` без шелфа (`SSA:598-616`); он же управляет squish QQS (раздел 2).
- Во время коллапса при раскрытом QS: `setShouldShowShelfOnly(true)` (`NPVC:1316-1343`), то есть остаётся только шелф уведомлений.
- Overscroll и `mOverExpansion` - см. раздел 3.3.
- Высота панели для расчётов клипа: `calculateBottomClippingBound` (`QSC:1579-1587`).

---

## 7. Коллапс

### 7.1 Свайп вверх

- QS раскрыт, касание в QS-области с `yDiff < 0`: `onIntercept`/`onTouch` ведут QS по пальцу; на отпускании `flingQsWithCurrentVelocity` -> `FLING_COLLAPSE` (QQS, `QSC:2099-2103`, цель `getMinExpansionHeight`, `QSC:2002-2007`). Если скорость вверх сильная, QS сворачивается до QQS (не до нуля).
- Одно движение, которое закрывает всю шторку с раскрытого QS: `isGoingBetweenClosedShadeAndExpandedQs` (`QSC:675-682`): `expanded && !tracking && !expansionAnimating && !expansionFromOverscroll`. Тогда панель тянется, и QS закрывается пропорционально (`NPVC:1906-1931`).
- Панель: `endMotionEvent` (`NPVC:2932-2993`) -> `fling(vel, expand=false)` -> `NPVC:3039-3050` (`target = 0`, `setClosing(true)`).
- Программно: `animateCloseQs(animateAway)` (`QSC:1963-1973`) -> `FLING_COLLAPSE` (QQS) или `FLING_HIDE` (до 0).

### 7.2 Тап вне шторки

- Legacy: `NPVC.onEmptySpaceClick` (`NPVC:3310-3312`) -> `onMiddleClicked` (`NPVC:2205-2234`): действия только в `KEYGUARD` (face auth, подсказка) и `SHADE_LOCKED` (переход в keyguard, если QS не раскрыт). Сам "свернуть шторку тапом снаружи" обеспечивает scrim (5.2, предположение).
- Compose: `onScrimClicked` (см. 5.2).

### 7.3 Назад

- Compose: `ShadeBackActionInteractorImpl.kt:34-48`: если QS раскрыт -> переход в `Scenes.Shade` (QQS), либо в `Home` при `fullyCollapse` / двойной / split (`:38-44`). `canBeCollapsed` = `isAnyExpanded && !isUserInteracting` (`:50-52`). `onBackPressed` -> `animateCollapseQs(false)` (`:54-56`).
- Оверлей QS: `Back` и `Swipe.Up` скрывают оверлей (`qs/ui/viewmodel/QuickSettingsShadeOverlayActionsViewModel.kt:50-51`), `Swipe.Down(fromSource = TopEdgeStartHalf)` открывает уведомления (`:55`).
- Legacy: `NPVC.collapse(delayed, speedUp)` (`NPVC:1316-1338`) и `collapseWithDuration` (`NPVC:1319-1322`) для программного сворачивания.

---

## 8. Рекомендации для порта на iOS

Эти значения переносятся напрямую (в "pt" вместо "dp", 1 dp ~ 1 pt для iPhone 8 при @2x):

1. **Один прогресс**: `H` (высота панели) и `q` (доля QS) из раздела 1. QQS-фаза: `q = 0`, `H` растёт; QS-фаза: `q` от 0 до 1 при `H >= Hqs_min`.
2. **Squish**: `s = clamp(0.1 + 0.9 * f_stack, 0, 1)`, где `f_stack = visibleStackHeight / stackEndHeight` (`QSVM:628-630`, `SSA:598-616`). QQS-плитки масштабируются по высоте и центрируются.
3. **Параллакс**: `headerY = -0.175 * H` при свёрнутом QS (`QSC:784`), далее lerp к 0 по `appearAmount`.
4. **Альфа контента QS**: `getContentAlpha(panelFraction)` (`SIA:24-27`).
5. **Scrim**: `getNotificationScrimAlpha(qFraction)` (`SIA:13-16`).
6. **Header morph**: прогресс `q` для MotionLayout-подобного перехода шапки (`SHC:621-626`); альфа шапки `getContentAlpha(shadeFraction)` (`SHC:225`).
7. **Порог касания/жеста**: slop на iOS - системный (`UIPanGestureRecognizer`), **предположение**; falsing порог `60 pt` (`qs_falsing_threshold`, `dimens.xml:858`); порог скорости **125 pt/s** (`SwipeDetector.kt:44`), позиционный **56 pt** (`DraggableHandler.kt:59-60`).
8. **Решение о раскрытии** (раздел 3.2): `flingExpands(vel) = |vel| < minVel ? (q > 0.5 || H_frac > 0.5) : vel > 0`. Значение `minVel` не найдено в дереве (платформа), **предположение**: брать 125 pt/s из Compose-порога.
9. **Длительности**: открытие 0.4 с, закрытие 0.6 с, dismiss 0.5 с, клик/тап 368 мс, смена направления 350 мс, пружина возврата 400 мс, overshoot `16 pt * k` (`k = lerp(0.2, 1, saturate(vel / (highVel*0.5)))`), кривая `FAST_OUT_SLOW_IN = (0.4, 0, 0.2, 1)`.
10. **Пружины** (если нужна физика вместо кривых): attach/detach `stiffness 380, damping 0.9`; opacity `1200 / 0.99` (`VECS:156-158`). Высоты для "магнитного" detach: `visible 24 pt`, `preDetach 0.25`, `detach 80 pt`, `attach 40 pt` (`VECS:146-149`).
11. **Прямое открытие QS**: два пальца от верхнего края статус-бара (`QSC:616-650`, `SUA:52`); одиночный тап по QQS/заголовку (`QSC:733-770`); на iOS - кастомный edge-pan + двухпальцевый pan.
12. **Коллапс**: свайп вверх от QS -> QQS (цель `minExpansionHeight`); свайп вверх от QQS -> закрытие шторки (одно движение, `QSC:675-682`); назад -> QQS (`ShadeBackActionInteractorImpl.kt:34-48`).

---

## 9. Чего в дереве нет (ограничения)

- **`FlingAnimationUtils`** (`getMinVelocityPxPerSecond`, `getHighVelocityPxPerSecond`, `apply`): класс не найден в `upstream/` (платформенный код). Числа `minVel` и `highVel` **неизвестны** по этому дереву.
- **Системный `ViewConfiguration`** (touch slop, ambiguous gesture multiplier): значения не в дереве.
- **`MotionScheme` (material3)**: `slowSpatialSpec`, `defaultSpatialSpec` и т.п. не найдены в дереве. Их конкретные пружины **неизвестны**.
- **Значения флагов** (`scene_container`, `notification_shade_blur`, `shade_qsvisible_logic`, `dual_shade`): видны описания в `systemui.aconfig`, но дефолты заданы вне дерева.
- **`TouchAnimator` (`SUI/src/com/android/systemui/qs/TouchAnimator.java`)**: не используется ни в одном месте дерева, кроме собственного теста `SUI/multivalentTests/.../TouchAnimatorTest.java`. Мёртвый код. Не переносить как источник motion.
- **`QSExpansionPathInterpolator` (`SUI/src/com/android/systemui/qs/QSExpansionPathInterpolator.kt`)**: использований нет (только сам класс). Мёртвый код, его кривая `(0,0,x2,1)` не применяется.
- **Scrim-клик в legacy**: обработчик не найден (см. 5.2).

---

## 10. Сводка по главным цифрам

| Параметр | Значение | Файл:строка |
|---|---|---|
| Параллакс QS | 0.175 | `NPVC:243` |
| Overshoot открытия | `panel_overshoot_amount` = 16 dp | `values/dimens.xml:899`, `NPVC:1002` |
| Открытие (fling) | max length 0.4 s (после loadDimens) | `NPVC:1003-1004` |
| Закрытие (fling) | 0.6 s, speedUp 0.6 | `NPVC:720-723`, `SVC:119-120` |
| Dismiss | 0.5 s, speedUp 0.6, x2 0.6, y2 0.84 | `NPVC:725-730` |
| Открытие без скорости | 350 ms | `NPVC:245`, `NPVC:1459` |
| Возврат overshoot | 400 ms | `NPVC:246`, `NPVC:3052-3068` |
| QS клик | 368 ms, `TOUCH_RESPONSE` | `QSC:2034-2035` |
| QS смена направления | 350 ms | `QSC:2038-2044` |
| QS size change | 300 ms | `QSC:957` |
| Порог falsing QS | 60 dp | `dimens.xml:858`, `QSC:472` |
| Falsing x1.5 после тапа | 1.5 | `SVC:112-113` |
| Окно "с лаунчера" | 300 ms | `NPVC:257` |
| Порог скорости (Compose) | 125 dp/s | `SwipeDetector.kt:44` |
| Позиционный порог (Compose) | 56 dp | `DraggableHandler.kt:59-60` |
| Squish min | 0.1 | `QSVM:628-630` |
| QS content fade | 0.43 .. 0.95 | `FromShadeToQuickSettingsTransition.kt:37-38` |
| Footer fade | 0..83 ms | `FromShadeToQuickSettingsTransition.kt:35` |
| QQS tile fade | 0..0.5 | `FromShadeToQuickSettingsTransition.kt:49` |
| Header collapsed fade | 0..0.14 | `FromShadeToQuickSettingsTransition.kt:62` |
| Header expanded fade | 0.58.. | `FromShadeToQuickSettingsTransition.kt:67` |
| Scrim alpha | `easeInOut(0..0.5)` | `SIA:13-16` |
| Content alpha | `easeInOut(0.3..1)` | `SIA:24-27` |
| Шаг QQS->QS в idle | 0.5 | `QSFC:1082` |
| Early expansion | 1e-6 | `QSVM:622` |
| Attach/detach spring | 380 / 0.9 | `VECS:156-157` |
| Opacity spring | 1200 / 0.99 | `VECS:158` |

---

## 11. Что проверено, что нет

Проверено чтением: весь путь legacy (touch, fling, clip, scrim, header), Compose QS (VM, STL, squish, переходы), scene-жесты (SUA, DraggableHandler, SwipeDetector), пружины mechanics (VECS), интерполяторы (INTERP), scrim-интерполяторы (SIA, SCRIM).

Не проверено: фактические значения флагов в сборке, платформенные FlingAnimationUtils и ViewConfiguration, MotionScheme материал3, точная раскладка ShadeHeader MotionLayout (constraint sets `CombinedShadeHeadersConstraintManagerImpl.kt` не разбирались подробно), поведение на устройстве.
