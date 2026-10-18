#import "LQSStrings.h"
#import "LQSPanelViewController.h"
#import <objc/message.h>
#import "LQSModel.h"
#import "LQSTheme.h"
#import "LQSViews.h"
#import "LQSVectorIcon.h"
#import "LQSBackends.h"
#import "LQSDetailDialog.h"
#import "LQSNotificationStack.h"
#import "LQSEditor.h"
#import "LQSMediaCard.h"
#import "LQSLayout.h"

NSString *const LQSLiveInfoChangedNotification = @"LQSLiveInfoChangedNotification";

// Grid (docs/qs-tiles-tokens.md): 4 columns, 4 rows per page, QQS 2 rows.
// values/config.xml:62-68 (portrait 4 columns, 4 rows/page, QQS 2 rows) and
// values-land/config.xml:24-30 (landscape 8 columns, 2 rows/page, QQS 1 row).
static NSInteger kColumns = 4;
static NSInteger kRowsPerPage = 4;
static NSInteger kQQSRows = 2;
static BOOL gLandscape;
static void UpdateGrid(CGSize size) {
    gLandscape = size.width > size.height;
    kColumns = gLandscape ? 8 : 4;
    kRowsPerPage = gLandscape ? 2 : 4;
    kQQSRows = gLandscape ? 1 : 2;
}
static const CGFloat kBounce = 8; // BounceableTileViewModel BounceSize

typedef struct { NSInteger page, row, col, span; } LQSCell;

// splitInRowsSequence: fill rows left to right; a tile that does not fit starts a new row.
static NSArray<NSValue *> *PlaceEntries(NSArray<LQSTileEntry *> *entries, NSInteger *pagesOut) {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger row = 0, col = 0;
    for (LQSTileEntry *e in entries) {
        NSInteger span = LQSTileSpan(e.size);
        if (col + span > kColumns) { row++; col = 0; }
        LQSCell c = {row / kRowsPerPage, row % kRowsPerPage, col, span};
        [out addObject:[NSValue valueWithBytes:&c objCType:@encode(LQSCell)]];
        col += span;
    }
    if (pagesOut) *pagesOut = MAX(1, (col == 0 ? row : row + 1) / kRowsPerPage + (((col == 0 ? row : row + 1) % kRowsPerPage) ? 1 : 0));
    return out;
}

// ShadeInterpolation.interpolateEaseInOut / getContentAlpha (SIA:13-27).
static CGFloat EaseInOut(CGFloat f) {
    CGFloat m = f * 1.2 - 0.2;
    if (m <= 0) return 0;
    CGFloat o = 1 - m;
    return 1 - 0.5 * (1 - cos(M_PI * o * o));
}
static CGFloat Range(CGFloat x, CGFloat a, CGFloat b) { return MAX(0, MIN(1, (x - a) / (b - a))); }
// ShadeInterpolation.getContentAlpha: constrainedMap(0, 1, 0.3, 1, fraction).
// Fade QS content together; there is no separate glyph-height opacity rule.
static CGFloat ContentAlpha(CGFloat f) { return EaseInOut(Range(f, 0.3, 1)); }
static CGFloat Lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }

@interface LQSPanelViewController () <UIGestureRecognizerDelegate>
@end

// Drawing needs enough vertical room for whole tiles throughout expansion.
// Hit-testing still stops at the current grid, so notifications/media below
// compact QS keep receiving touches. Horizontal paging stays clipped.
@interface LQSGridViewport : UIView
@property (nonatomic) CGFloat interactionHeight;
@end

@implementation LQSGridViewport
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return point.y <= self.interactionHeight && [super pointInside:point withEvent:event];
}
@end

@implementation LQSPanelViewController {
    UIView *_backdrop, *_panelColor, *_notificationSurface, *_content, *_footer, *_actions;
    LQSGridViewport *_gridClip;
    UIVisualEffectView *_blur;
    LQSHeaderView *_header;
    LQSBrightnessView *_brightness;
    LQSNotificationStack *_notifs;
    LQSPageDots *_dots;
    UILabel *_feedback;
    LQSIconButton *_editButton, *_settingsButton, *_powerButton;
    NSMutableArray<LQSTileView *> *_tiles;
    NSArray<NSValue *> *_cells;
    NSInteger _pageCount;
    CGFloat _page;          // fractional page while paging
    CGFloat _pageStart;
    LQSSettings *_settings;
    CGFloat _progress;      // native presentation 0...1
    CGFloat _q;             // QQS (0) -> QS (1)
    CGFloat _qStart;
    CADisplayLink *_qLink, *_settleLink, *_pageLink;
    CGFloat _qFrom, _qTo, _settleFrom, _settleTo, _pageFrom, _pageTo;
    CFTimeInterval _qStartTime, _qDuration, _settleStart, _settleDuration, _pageStartTime;
    NSTimer *_liveTimer;
    BOOL _liveRefreshPending;
    LQSDetailDialog *_dialog;
    NSMapTable<LQSTileView *, NSValue *> *_bounce; // tile -> CGPoint(dx, dw) while pressed
    CFTimeInterval _pressStart;
    UIPanGestureRecognizer *_vpan, *_hpan;
    NSInteger _listMode;    // drag in the notification list: 0 scroll, 1 expands QS, 2 closes the shade
    BOOL _listDecided;      // the mode is chosen once, on the first movement of the drag
    CGFloat _listModeY;
    LQSEditor *_editor;
    LQSMediaCard *_media;
}

#pragma mark - Geometry (iPhone 8: 375 x 667 pt)

- (CGFloat)qqsTop { return [_header collapsedHeight] + 8; }                  // qqsHeaderHeight + tile margin (assumption)
- (CGFloat)qsBrightnessTop { return gLandscape ? [_header collapsedHeight] + 8 : [_header collapsedHeight] + 80 + 16; } // landscape: no big header   // qqsPadding + qs_panel_padding_top + VerticalPadding
- (CGFloat)brightnessHeight { return 52; }                                   // thumb 52dp (track 40 + 2 x 6 padding)
- (CGFloat)qsGridTop { return [self qsBrightnessTop] + (_brightness.hidden ? 0 : [self brightnessHeight] + 8); }
- (CGFloat)tileHeight { return MIN([LQSTheme tileHeight], [self cellWidth]); }
- (CGFloat)rowHeight:(CGFloat)squish { return [self tileHeight] * squish; }
- (CGFloat)gridHeightRows:(NSInteger)rows squish:(CGFloat)s { return rows * [self rowHeight:s] + (rows - 1) * [LQSTheme tileGap]; }
- (CGFloat)mediaExtra { return _media.hasMedia ? 16 + [LQSMediaCard height] : 0; } // QQS: tiles, then media (16dp)
- (CGFloat)qqsBottom { return [self qqsTop] + [self gridHeightRows:MIN(kQQSRows, [self usedRowsOnFirstPage]) squish:1] + [self mediaExtra] + 24; } // qqs_layout_padding_bottom
- (CGFloat)qsBottom { return [self qsGridTop] + [self gridHeightRows:kRowsPerPage squish:1] + 48 + 8 + 40 + 4; } // pager footer 48, actions
- (CGFloat)cellWidth { return (self.view.bounds.size.width - 2 * [LQSTheme sideInset] - (kColumns - 1) * [LQSTheme tileGap]) / kColumns; }
- (BOOL)updateGridForBounds {
    NSInteger oldColumns = kColumns, oldRows = kRowsPerPage;
    CGSize size = self.view.bounds.size;
    UpdateGrid(size);
    if (size.width > 0 && size.height > 0) {
        CGFloat bottom = size.height - self.view.safeAreaInsets.bottom - 12;
        CGFloat available = bottom - [self qsGridTop] - 48 - 4 - 40;
        kRowsPerPage = LQSRowsFitting((int)kRowsPerPage, available, [self tileHeight], [LQSTheme tileGap]);
    }
    return oldColumns != kColumns || oldRows != kRowsPerPage;
}
- (NSInteger)usedRowsOnFirstPage {
    NSInteger rows = 0;
    for (NSValue *v in _cells) { LQSCell c; [v getValue:&c]; if (c.page == 0) rows = MAX(rows, c.row + 1); }
    return MAX(1, rows);
}

#pragma mark - View

- (void)loadView {
    UIView *root = [UIView new];
    root.backgroundColor = UIColor.clearColor;
    self.view = root;
    _settings = [LQSSettings current];
    _bounce = [NSMapTable weakToStrongObjectsMapTable];

    _backdrop = [UIView new];
    _backdrop.userInteractionEnabled = YES;
    [_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped)]];
    [root addSubview:_backdrop];
    _panelColor = [UIView new];
    _panelColor.backgroundColor = [LQSTheme shadePanel];
    _panelColor.userInteractionEnabled = NO;
    [_backdrop addSubview:_panelColor];

    // This surface reaches the bottom even while the content reveal is partial.
    _notificationSurface = [UIView new];
    _notificationSurface.userInteractionEnabled = NO;
    _notificationSurface.backgroundColor = [LQSColor(@"surface_effect_0") colorWithAlphaComponent:0.5];
    _notificationSurface.layer.cornerRadius = 28;
    _notificationSurface.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [_backdrop addSubview:_notificationSurface];

    _content = [UIView new];
    [root addSubview:_content];

    _notifs = [LQSNotificationStack new];
    _notifs.showsBackground = NO; // drawn outside the content's reveal mask
    __weak typeof(self) weakSelf = self;
    _notifs.requestDismiss = ^{ [weakSelf.delegate panelRequestsDismiss:weakSelf]; };
    _notifs.openSettingsURL = ^(NSString *url) {
        UIApplication *app = UIApplication.sharedApplication;
        SEL sbOpen = NSSelectorFromString(@"applicationOpenURL:");
        if ([app respondsToSelector:sbOpen]) ((void (*)(id, SEL, id))objc_msgSend)(app, sbOpen, [NSURL URLWithString:url]);
        [weakSelf.delegate panelRequestsDismiss:weakSelf];
    };
    [_content addSubview:_notifs];
    _media = [LQSMediaCard new];
    _media.onChange = ^{ [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ [weakSelf.view setNeedsLayout]; [weakSelf.view layoutIfNeeded]; } completion:nil]; };
    [_content addSubview:_media];

    _header = [LQSHeaderView new];
    _header.onClockTap = ^{
        if ([LQSBackends realActionsEnabled] && [LQSBackends stateFor:@"screenrecord"] == LQSBackendStateOn && [LQSBackends recordingCountdown] == 0) {
            [weakSelf confirmStopRecording];
        } else [weakSelf openSettingsURL:@"clock-alarm:"];
    };
    [_content addSubview:_header];

    _brightness = [LQSBrightnessView new];
    _brightness.value = [LQSModel shared].mockBrightness;
    _brightness.onAutoToggle = ^(BOOL on) { [weakSelf openSettingsURL:@"prefs:root=DISPLAY"]; }; // iOS auto-brightness toggle: Settings (no safe setter verified)
    [_brightness addTarget:self action:@selector(brightnessChanged) forControlEvents:UIControlEventValueChanged];
    // Brightness mirror: while dragging only the slider stays visible (BrightnessMirrorController).
    _brightness.onDragChanged = ^(BOOL d) { [weakSelf mirror:d]; };
    [_content addSubview:_brightness];

    _gridClip = [LQSGridViewport new];
    _gridClip.clipsToBounds = YES;
    [_content addSubview:_gridClip];

    // PaginatedGridLayout FooterBar 48dp: page dots centred, edit at the end.
    _footer = [UIView new];
    [_content addSubview:_footer];
    _dots = [LQSPageDots new];
    _dots.userInteractionEnabled = NO;
    [_footer addSubview:_dots];
    _feedback = [UILabel new]; // requestToggleTextFeedback (icon tiles): "<label> <state>" in the footer
    _feedback.font = [LQSTheme sansWithSize:14 weight:500];
    _feedback.textColor = [LQSTheme onSurface];
    _feedback.textAlignment = NSTextAlignmentCenter;
    _feedback.alpha = 0;
    [_footer addSubview:_feedback];
    _editButton = [[LQSIconButton alloc] initWithIcon:@"ic_edit" side:20];
    _editButton.fill = UIColor.clearColor;
    _editButton.accessibilityLabel = LQSL(@"accessibility_quick_settings_edit");
    [_editButton addTarget:self action:@selector(editTapped) forControlEvents:UIControlEventTouchUpInside];
    [_footer addSubview:_editButton];

    // FooterActions: 40dp circles at the end: settings, power (FooterActions.kt:234-266).
    _actions = [UIView new];
    [_content addSubview:_actions];
    _settingsButton = [[LQSIconButton alloc] initWithIcon:@"ic_qs_footer_settings" side:20];
    _settingsButton.accessibilityLabel = LQSL(@"accessibility_quick_settings_settings");
    [_settingsButton addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    _powerButton = [[LQSIconButton alloc] initWithIcon:@"ic_qs_footer_power" side:20];
    _powerButton.fill = [LQSTheme primary]; // assumption: power uses the accent container
    _powerButton.glyph = [LQSTheme onPrimary];
    _powerButton.accessibilityLabel = LQSL(@"accessibility_quick_settings_power_menu");
    [_powerButton addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
    [_actions addSubview:_settingsButton];
    [_actions addSubview:_powerButton];

    _vpan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(verticalPan:)];
    _vpan.delegate = self;
    [root addGestureRecognizer:_vpan];
    _hpan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pagePan:)];
    _hpan.delegate = self;
    [_gridClip addGestureRecognizer:_hpan];
    // The list keeps its own scrolling; at its top a downward drag turns into QS
    // expansion, at its end an upward drag closes the shade (one continuous gesture).
    [_notifs.scrollView.panGestureRecognizer addTarget:self action:@selector(listPan:)];

    [self rebuildTiles];
    _state = LQSPanelStateCompact;
    // The preview host starts open; SpringBoard must never flash a fully open
    // frame before Install receives the native presenter's first progress.
    [self setPresentationProgress:[NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ? 0 : 1];
}

- (void)setOwnBackdrop:(BOOL)own {
    if (own) [self loadViewIfNeeded];
    _ownBackdrop = own;
    if (own && !_blur) {
        _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
        _blur.userInteractionEnabled = NO;
        // Keep effect intensity separate from the tint/scrim alpha.
        [self.view insertSubview:_blur belowSubview:_backdrop];
    }
    _blur.hidden = !own || _progress <= 0.001;
    [self.view setNeedsLayout];
}

- (void)updateBlurForProgress:(CGFloat)progress {
    if (!_blur) return;
    CGFloat p = MAX(0, MIN(1, progress));
    BOOL visible = _ownBackdrop && p > 0.001;
    _blur.alpha = p;
    _blur.hidden = !visible;
}

- (void)openSettingsURL:(NSString *)url {
    if (![LQSBackends realActionsEnabled]) return;
    UIApplication *app = UIApplication.sharedApplication;
    SEL sbOpen = NSSelectorFromString(@"applicationOpenURL:");
    if ([app respondsToSelector:sbOpen]) ((void (*)(id, SEL, id))objc_msgSend)(app, sbOpen, [NSURL URLWithString:url]);
    [self.delegate panelRequestsDismiss:self];
}

- (void)settingsTapped { LQSHapticTick(); [self openSettingsURL:@"prefs:root=ROOT"]; }
- (void)powerTapped {
    // Android opens the global actions (power) menu; iOS has no public equivalent,
    // so it opens Settings > General (Shut Down lives there). Assumption.
    LQSHapticTick();
    [self openSettingsURL:@"prefs:root=General"];
}

#pragma mark - Settings / tiles

- (void)reloadFromPreferences {
    _settings = [LQSSettings current];
    [[LQSModel shared] reloadLayoutFromPreferences];
    [self rebuildTiles];
}

- (void)rebuildTiles {
    for (UIView *v in _tiles) [v removeFromSuperview];
    _tiles = [NSMutableArray array];
    LQSModel *m = [LQSModel shared];
    __weak typeof(self) weakSelf = self;
    NSMutableArray *entries = [NSMutableArray array];
    for (LQSTileEntry *e in m.layout) {
        LQSTileSpec *spec = [m specForIdentifier:e.identifier];
        if (!spec) continue;
        [entries addObject:e];
        LQSTileView *t = [[LQSTileView alloc] initWithSpec:spec size:e.size];
        [self applyStateToTile:t animated:NO];
        [t addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileLongPressed:)];
        lp.minimumPressDuration = 0.4; // ViewConfiguration DEFAULT_LONG_PRESS_TIMEOUT
        [t addGestureRecognizer:lp];
        t.onPress = ^(LQSTileView *tile, BOOL pressed) { [weakSelf tile:tile pressed:pressed]; };
        [_gridClip addSubview:t];
        [_tiles addObject:t];
    }
    NSInteger pages = 1;
    [self updateGridForBounds];
    _cells = PlaceEntries(entries, &pages);
    _pageCount = pages;
    _page = MIN(_page, pages - 1);
    _brightness.showAuto = _settings.showAutoBrightness;
    _notifs.hidden = !_settings.showNotifications;
    [self.view setNeedsLayout];
}

- (void)applyStateToTile:(LQSTileView *)t animated:(BOOL)animated {
    NSString *ident = t.spec.identifier;
    BOOL real = [LQSBackends realActionsEnabled];
    if ([ident isEqualToString:@"internet"]) {
        // InternetTile: active when connected over Wi-Fi or mobile data; icon = signal bars.
        NSDictionary *info = real ? [LQSBackends liveInfo] : nil;
        if (!info) { t.on = [[LQSModel shared] isOn:ident]; t.iconOverride = @"ic_wifi_3"; return; }
        BOOL wifi = [info[@"wifiAssociated"] boolValue];
        BOOL cell = !wifi && ![info[@"noSIM"] boolValue] && [LQSBackends stateFor:@"cell"] == LQSBackendStateOn;
        [t setOn:(wifi || cell) animated:animated];
        NSInteger wb = MAX(0, MIN(3, [info[@"wifiBars"] integerValue])), cb = MAX(0, MIN(4, [info[@"cellBars"] integerValue]));
        t.iconOverride = wifi ? [NSString stringWithFormat:@"ic_wifi_%ld", (long)wb] // newStatusBarIcons 3-bar set
                       : cell ? [NSString stringWithFormat:@"ic_signal_cellular_%ld_4_bar", (long)cb]
                       : ([info[@"wifiOn"] boolValue] ? @"ic_wifi_0" : @"ic_qs_wifi_disconnected");
        return;
    }
    LQSBackendState bs = real ? [LQSBackends stateFor:ident] : LQSBackendStateUnsupported;
    t.iconText = real && [ident isEqualToString:@"screenrecord"] && [LQSBackends recordingCountdown] > 0
        ? [NSString stringWithFormat:@"%ld", (long)[LQSBackends recordingCountdown]] : nil;
    if (bs >= 0) { t.unavailable = NO; [t setOn:(bs == LQSBackendStateOn) animated:animated]; [[LQSModel shared] setOn:t.on forIdentifier:ident]; }
    else if (bs == LQSBackendStateUnavailable) { t.on = NO; t.unavailable = YES; }
    else { t.unavailable = NO; [t setOn:[[LQSModel shared] isOn:ident] animated:animated]; }
    if ([ident isEqualToString:@"cell"] && real && [[LQSBackends liveInfo][@"noSIM"] boolValue]) { t.on = NO; t.unavailable = YES; return; } // no SIM: mobile data unavailable
    if ([ident isEqualToString:@"cell"] && real) {
        NSInteger cb = MAX(0, MIN(4, [[LQSBackends liveInfo][@"cellBars"] integerValue]));
        t.iconOverride = t.on ? [NSString stringWithFormat:@"ic_signal_cellular_%ld_4_bar", (long)cb] : nil;
    }
}

- (NSString *)secondaryFor:(LQSTileView *)t info:(NSDictionary *)info {
    NSString *ident = t.spec.identifier;
    if ([LQSBackends isTransitioning:ident] || ([ident isEqualToString:@"screenrecord"] && [LQSBackends recordingCountdown] > 0)) return LQSL(t.on ? @"On" : @"Off");
    if ([ident isEqualToString:@"internet"]) {
        if ([info[@"wifiAssociated"] boolValue] && [info[@"wifiName"] length]) return info[@"wifiName"];
        if (t.on) { NSString *c = info[@"carrier"]; return c.length ? c : LQSL(@"On"); }
        return [info[@"wifiOn"] boolValue] ? LQSL(@"Networks available") : LQSL(@"Off");
    }
    return [LQSBackends secondaryLabelFor:ident info:info];
}

- (void)refreshRealStates { [self refreshRealStatesIncludingBrightness:YES]; }

- (void)refreshRealStatesIncludingBrightness:(BOOL)withBrightness {
    NSDictionary *info = [LQSBackends liveInfo];
    [_header applyLiveInfo:info];
    [_header refresh];
    _header.recording = [LQSBackends realActionsEnabled] && [LQSBackends stateFor:@"screenrecord"] == LQSBackendStateOn
        && [LQSBackends recordingCountdown] == 0 && ![LQSBackends isTransitioning:@"screenrecord"];
    if (![LQSBackends realActionsEnabled]) return;
    for (LQSTileView *t in _tiles) {
        [self applyStateToTile:t animated:(_progress > 0.5)];
        t.stateText = [self secondaryFor:t info:info];
    }
    if (!withBrightness || _brightness.dragging) return;
    CGFloat b = [LQSBackends brightnessControlSupported] ? [LQSBackends brightness] : -1;
    if (b >= 0) _brightness.value = b;
}

#pragma mark - Live updates while visible

- (void)startLiveUpdates {
    if (_liveTimer) return;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[LQSBackendsChangedNotification, LQSLiveInfoChangedNotification, UIScreenCapturedDidChangeNotification, @"BluetoothPowerChangedNotification", @"BluetoothDeviceConnectSuccessNotification",
                             @"BluetoothDeviceDisconnectSuccessNotification", @"BluetoothConnectionStatusChangedNotification",
                             NSProcessInfoPowerStateDidChangeNotification, UIDeviceBatteryLevelDidChangeNotification, UIDeviceBatteryStateDidChangeNotification]) {
        [nc addObserver:self selector:@selector(liveSourceChanged:) name:name object:nil];
    }
    __weak typeof(self) weakSelf = self;
    _liveTimer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { [weakSelf scheduleLiveRefresh]; }];
    [NSRunLoop.mainRunLoop addTimer:_liveTimer forMode:NSRunLoopCommonModes];
    [_notifs reload];
}

- (void)stopLiveUpdates {
    [_liveTimer invalidate];
    _liveTimer = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)liveSourceChanged:(NSNotification *)n { [self scheduleLiveRefresh]; }

- (void)scheduleLiveRefresh {
    if (_liveRefreshPending) return;
    _liveRefreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_liveRefreshPending = NO;
        if (self->_liveTimer) [self refreshRealStatesIncludingBrightness:NO];
        if (self->_dialog.superview && self->_dialog.kind == LQSDetailKindBluetooth) [self->_dialog reload];
    });
}

#pragma mark - Tile actions (Tile.kt:240-310)

- (void)confirmStopRecording {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LQSL(@"Stop recording") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LQSL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LQSL(@"Stop recording") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [LQSBackends setOn:NO forIdentifier:@"screenrecord"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDetailsFor:(NSString *)ident {
    [_dialog removeFromSuperview];
    BOOL net = [ident isEqualToString:@"wifi"] || [ident isEqualToString:@"internet"] || [ident isEqualToString:@"cell"];
    LQSDetailDialog *d = [[LQSDetailDialog alloc] initWithKind:net ? LQSDetailKindInternet : LQSDetailKindBluetooth];
    __weak typeof(self) weakSelf = self;
    d.openSettings = ^(NSString *tile) {
        typeof(self) s = weakSelf;
        [LQSBackends openSettingsFor:tile];
        [s->_dialog dismiss];
        [s.delegate panelRequestsDismiss:s];
    };
    d.stateChanged = ^{ [weakSelf scheduleLiveRefresh]; };
    _dialog = d;
    [d presentInView:self.view];
}

- (BOOL)hasDetails:(NSString *)ident { return [@[@"internet", @"wifi", @"bt"] containsObject:ident]; }

- (void)toggleTile:(LQSTileView *)tile {
    NSString *ident = tile.spec.identifier;
    if (![LQSBackends realActionsEnabled]) {
        if (_settings.demoStates) {
            BOOL on = !tile.on;
            [[LQSModel shared] setOn:on forIdentifier:ident];
            [tile setOn:on animated:YES];
        }
        return;
    }
    if ([ident isEqualToString:@"cell"] && [[LQSBackends liveInfo][@"noSIM"] boolValue]) { [tile contentBounce]; return; } // can't enable without a SIM
    LQSBackendState s = [LQSBackends stateFor:ident];
    if (s < 0) {
        if ([LQSBackends settingsURLFor:ident]) { [LQSBackends openSettingsFor:ident]; [self.delegate panelRequestsDismiss:self]; }
        return;
    }
    LQSBackendState after = [LQSBackends activate:ident];
    NSLog(@"[LineageQS] tile %@ %ld -> %ld", ident, (long)s, (long)after);
    [self applyStateToTile:tile animated:YES]; // backend retains only accepted requests
    tile.stateText = [self secondaryFor:tile info:[LQSBackends liveInfo]];
    for (NSNumber *d in @[@0.4, @1.2, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self applyStateToTile:tile animated:YES];
            tile.stateText = [self secondaryFor:tile info:[LQSBackends liveInfo]];
        });
    }
}

// mainClick: details for dual-target / internet tiles, launch for app tiles, toggle otherwise.
- (void)mainClick:(LQSTileView *)tile {
    NSString *ident = tile.spec.identifier;
    if ([self hasDetails:ident] && ([LQSBackends realActionsEnabled] || [ident isEqualToString:@"internet"])) { [self showDetailsFor:ident]; return; }
    if ([LQSBackends realActionsEnabled] && [LQSBackends kindFor:ident] == LQSBackendKindLaunch) {
        [LQSBackends activate:ident];
        [self.delegate panelRequestsDismiss:self];
        return;
    }
    [self toggleTile:tile];
}

- (void)tileTapped:(LQSTileView *)tile {
    LQSHapticTick();
    if (!tile.bouncesContainer) [tile contentBounce];
    BOOL iconOnly = tile.size == LQSTileSizeSmall;
    if (tile.spec.dualTarget && (iconOnly || tile.lastTouchInIcon)) [self toggleTile:tile]; // toggleClick
    else [self mainClick:tile];
    if (tile.spec.toggleable && iconOnly) [self showToggleFeedback:tile];
}

- (void)showToggleFeedback:(LQSTileView *)tile {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *state = tile.unavailable ? LQSL(@"tile_unavailable") : LQSL(tile.on ? @"On" : @"Off");
        self->_feedback.text = [NSString stringWithFormat:@"%@ • %@", tile.spec.title, state];
        [UIView animateWithDuration:0.2 animations:^{ self->_feedback.alpha = 1; self->_dots.alpha = 0; }];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFeedback) object:nil];
        [self performSelector:@selector(hideFeedback) withObject:nil afterDelay:2.0];
    });
}
- (void)hideFeedback { [UIView animateWithDuration:0.2 animations:^{ self->_feedback.alpha = 0; self->_dots.alpha = 1; }]; }

- (void)tileLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    LQSTileView *tile = (LQSTileView *)g.view;
    LQSHapticTick();
    [tile cancelTrackingWithEvent:nil];
    // Small available dual-target tiles: long press = main click (details); else settings.
    if (tile.size == LQSTileSizeSmall && tile.spec.dualTarget && !tile.unavailable) { [self mainClick:tile]; return; }
    if (![LQSBackends realActionsEnabled] || ![LQSBackends settingsURLFor:tile.spec.identifier]) return;
    [LQSBackends openSettingsFor:tile.spec.identifier];
    [self.delegate panelRequestsDismiss:self];
}

// Container bounce: the pressed tile grows by 8dp towards its end (start on the
// last column) and the neighbour on that side shrinks (BounceableInfo.kt:33-53).
- (void)tile:(LQSTileView *)tile pressed:(BOOL)pressed {
    NSUInteger i = [_tiles indexOfObjectIdenticalTo:tile];
    if (i == NSNotFound || UIAccessibilityIsReduceMotionEnabled()) return;
    LQSCell c; [_cells[i] getValue:&c];
    BOOL lastCol = c.col + c.span >= kColumns;
    NSInteger ni = lastCol ? (NSInteger)i - 1 : (NSInteger)i + 1;
    LQSTileView *n = nil;
    if (ni >= 0 && ni < (NSInteger)_tiles.count) {
        LQSCell nc; [_cells[ni] getValue:&nc];
        if (nc.page == c.page && nc.row == c.row) n = _tiles[ni];
    }
    void (^apply)(void) = ^{
        if (pressed) {
            [self->_bounce setObject:[NSValue valueWithCGPoint:CGPointMake(lastCol ? -kBounce : 0, kBounce)] forKey:tile];
            if (n) [self->_bounce setObject:[NSValue valueWithCGPoint:CGPointMake(lastCol ? 0 : kBounce, -kBounce)] forKey:n];
        }
        else { [self->_bounce removeObjectForKey:tile]; if (n) [self->_bounce removeObjectForKey:n]; }
        [self layoutTilesOnly];
    };
    if (pressed) {
        _pressStart = CACurrentMediaTime();
        UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:[[UISpringTimingParameters alloc] initWithMass:1 stiffness:1500 damping:2 * sqrt(1500) initialVelocity:CGVectorMake(0, 0)]];
        [a addAnimations:apply];
        [a startAnimation];
    } else {
        // animateToRest waits until the bounce reached 75% (max 1 s).
        CFTimeInterval wait = MAX(0, 0.06 - (CACurrentMediaTime() - _pressStart));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:[[UISpringTimingParameters alloc] initWithMass:1 stiffness:1500 damping:2 * sqrt(1500) initialVelocity:CGVectorMake(0, 0)]];
            [a addAnimations:apply];
            [a startAnimation];
        });
    }
}

- (void)mirror:(BOOL)on {
    [UIView animateWithDuration:on ? 0.15 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (UIView *v in self->_content.subviews) if (v != self->_brightness) v.alpha = on ? 0 : 1;
        self->_backdrop.alpha = on ? 0.15 : MAX(0, MIN(1, self->_progress));
    } completion:^(BOOL f) { if (!on) [self layoutAll]; }];
}

- (void)brightnessChanged {
    [LQSModel shared].mockBrightness = _brightness.value;
    if (![LQSBackends brightnessControlSupported]) return;
    static CFAbsoluteTime last;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last >= 0.03) { last = now; [LQSBackends setBrightness:_brightness.value]; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushBrightness) object:nil];
    [self performSelector:@selector(flushBrightness) withObject:nil afterDelay:0.06];
}
- (void)flushBrightness { [LQSBackends setBrightness:_brightness.value]; }

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutAll];
}

- (void)layoutAll {
    CGRect b = self.view.bounds;
    BOOL gridChanged = [self updateGridForBounds];
    if (gridChanged && _tiles.count) { [self rebuildTiles]; return; }
    CGFloat w = b.size.width, inset = [LQSTheme sideInset];
    _backdrop.frame = b;
    _blur.frame = b;
    _panelColor.frame = b;
    [self updateBlurForProgress:_progress];
    _content.bounds = CGRectMake(0, 0, b.size.width, b.size.height);
    _content.center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    CGFloat q = _q, p = MAX(0, MIN(1, _progress));
    _header.frame = CGRectMake(0, 0, w, [_header expandedHeight]);
    _header.expansion = gLandscape ? 0 : q; // landscape keeps the one-row header

    // Brightness: only in QS (showSlider 1 = panel, not QQS); fades in with the QS content.
    _brightness.frame = CGRectMake(inset, [self qsBrightnessTop] - (1 - q) * 40, w - 2 * inset, [self brightnessHeight]);
    _brightness.alpha = Range(q, 0.43, 0.95);
    _brightness.userInteractionEnabled = q > 0.95;

    // Keep the drawing viewport full-height. Interpolating its clipping edge
    // between row counts slices through QS-only tiles as they fade in.
    CGFloat squish = (q > 0) ? 1 : 0.1 + 0.9 * p; // constrainSquishiness(0.1 + 0.9x)
    NSInteger qqsRows = MIN(kQQSRows, [self usedRowsOnFirstPage]);
    CGFloat qqsH = [self gridHeightRows:qqsRows squish:squish], qsH = [self gridHeightRows:kRowsPerPage squish:1];
    CGFloat top = Lerp([self qqsTop], [self qsGridTop], q);
    _gridClip.frame = CGRectMake(0, top, w, MAX(0, b.size.height - top));
    _gridClip.interactionHeight = Lerp(qqsH, qsH, q) + kBounce;
    [self layoutTilesOnly];

    CGFloat qsGridBottom = [self qsGridTop] + qsH;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    _footer.frame = CGRectMake(inset, LQSFooterTop(b.size.height, safe.bottom) + (1 - q) * 40, w - 2 * inset, 48);
    _footer.alpha = Range(q, 0.9, 1);
    _footer.userInteractionEnabled = q > 0.95;
    _dots.frame = _footer.bounds;
    _dots.pages = _pageCount;
    _dots.position = _page;
    _feedback.frame = _footer.bounds;
    _editButton.frame = CGRectMake(_footer.bounds.size.width - 40, 4, 40, 40);
    _editButton.hidden = !_settings.editorEnabled;
    _editor.frame = b;
    CGFloat actionsLeft = MAX(inset, safe.left + 8), actionsRight = MAX(inset, safe.right + 8);
    CGFloat actionsTop = LQSActionRowTop(b.size.height, safe.bottom);
    _actions.frame = CGRectMake(actionsLeft, actionsTop, MAX(0, w - actionsLeft - actionsRight), 40);
    _actions.alpha = _footer.alpha;
    _actions.userInteractionEnabled = q > 0.95;
    _powerButton.frame = CGRectMake(_actions.bounds.size.width - 40, 0, 40, 40);
    _settingsButton.frame = CGRectMake(_actions.bounds.size.width - 40 - 8 - 40, 0, 40, 40);

    CGFloat qqsGridBottom = [self qqsTop] + qqsH;
    _media.hidden = !_media.hasMedia;
    _media.frame = CGRectMake(inset, Lerp(qqsGridBottom + 16, qsGridBottom + 56, q), w - 2 * inset, [LQSMediaCard height]);
    _media.alpha = 1 - Range(q, 0, 0.5);
    _media.userInteractionEnabled = q < 0.05;
    // Notifications: under QQS, pushed down with the QS bottom while expanding.
    CGFloat nTop = Lerp([self qqsBottom] + 12 - (1 - squish) * qqsH, [self qsBottom] + 16, q); // extra 12pt gap above the notification scrim (matches Pixel screenshots)
    _notifs.frame = CGRectMake(0, nTop, w, MAX(0, b.size.height - nTop));
    _notifs.alpha = 1 - Range(q, 0, 0.5);
    _notifs.userInteractionEnabled = q < 0.05 || _listMode != 0;
    CGFloat surfaceTop = MAX(0, MIN(b.size.height, nTop + _content.transform.ty));
    _notificationSurface.frame = CGRectMake(0, surfaceTop, w, b.size.height - surfaceTop);
    _notificationSurface.alpha = _notifs.alpha;
    _notificationSurface.hidden = _notifs.hidden;
}

- (void)layoutTilesOnly {
    CGFloat q = _q, p = MAX(0, MIN(1, _progress)), w = self.view.bounds.size.width, inset = [LQSTheme sideInset];
    CGFloat cw = [self cellWidth], gap = [LQSTheme tileGap];
    CGFloat squish = (q > 0) ? 1 : 0.1 + 0.9 * p;
    CGFloat pageOffset = _page * w * q; // pages slide horizontally (InterPageSpacing: page = full width incl. 16dp margins)
    CGFloat qsTop = [self qsGridTop], qqsTop = [self qqsTop], clipTop = _gridClip.frame.origin.y;
    for (NSUInteger i = 0; i < _tiles.count && i < _cells.count; i++) {
        LQSTileView *t = _tiles[i];
        LQSCell c; [_cells[i] getValue:&c];
        BOOL inQQS = c.page == 0 && c.row < kQQSRows;
        CGFloat rowH = [self rowHeight:inQQS ? squish : 1];
        CGFloat x = inset + c.col * (cw + gap) + c.page * w - pageOffset;
        CGFloat width = c.span * cw + (c.span - 1) * gap;
        NSValue *bv = [_bounce objectForKey:t];
        if (bv) { CGPoint d = bv.CGPointValue; x += d.x; width += d.y; }
        CGFloat yQS = qsTop + c.row * ([self tileHeight] + gap);
        CGFloat yQQS = qqsTop + c.row * (rowH + gap);
        // QS-only tiles ride with the grid (they belong to the same expanding QS panel).
        CGFloat y = inQQS ? Lerp(yQQS, yQS, q) : Lerp(qqsTop, qsTop, q) + c.row * ([self tileHeight] + gap);
        CGFloat height = inQQS ? Lerp(rowH, [self tileHeight], q) : [self tileHeight];
        // Small tiles stay square at rest on both narrow and wide displays.
        CGFloat tileWidth = c.span == 1 ? MIN(width, [self tileHeight]) : width;
        // verticalSquish changes layout height and centers normal-size content;
        // it does not scale glyphs or give them a separate height-based fade.
        t.squish = inQQS ? squish : 1;
        t.transform = CGAffineTransformIdentity;
        t.bounds = CGRectMake(0, 0, tileWidth, height);
        t.center = CGPointMake(x + width / 2, y - clipTop + height / 2);
        // QS-only tiles fade in over [0.43, 0.95] (FromShadeToQuickSettingsTransition).
        t.alpha = inQQS ? 1 : Range(q, 0.43, 0.95);
        t.userInteractionEnabled = inQQS ? (q < 0.05 || q > 0.95) : q > 0.95;
    }
}

#pragma mark - State / expansion

- (void)setNotificationsMode:(BOOL)on {
    _notificationsMode = on;
    if (on && _state != LQSPanelStateCompact) [self setState:LQSPanelStateCompact animated:NO];
}

- (void)setState:(LQSPanelState)state animated:(BOOL)animated {
    if (state == LQSPanelStateEditor) {
        if (!_settings.editorEnabled) return;
        if (_q < 0.999) [self setQ:1];
        _state = state;
        [self showEditor:animated];
        return;
    }
    if (_state == LQSPanelStateEditor) [self hideEditor:animated];
    _state = state;
    [self animateQTo:(state == LQSPanelStateExpanded ? 1 : 0) velocity:0 animated:animated];
}

- (void)editTapped { LQSHapticTick(); [self setState:LQSPanelStateEditor animated:YES]; }

// ToEditMode: tween(500); QS content fades over [0, 0.5], the editor over [0.5, 1].
- (void)showEditor:(BOOL)animated {
    if (_editor) return;
    _editor = [[LQSEditor alloc] initWithFrame:self.view.bounds];
    _editor.topInset = 20; // iPhone 8 status bar (statusBarsPadding)
    __weak typeof(self) weakSelf = self;
    _editor.onExit = ^{ [weakSelf setState:LQSPanelStateExpanded animated:YES]; };
    _editor.alpha = 0;
    [self.view addSubview:_editor];
    NSTimeInterval d = (animated && !UIAccessibilityIsReduceMotionEnabled()) ? 0.25 : 0;
    [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ self->_content.alpha = 0; } completion:^(BOOL f) {
        [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ self->_editor.alpha = 1; } completion:nil];
    }];
}

- (void)hideEditor:(BOOL)animated {
    LQSEditor *ed = _editor;
    _editor = nil;
    [self rebuildTiles];
    [self refreshRealStates];
    NSTimeInterval d = (animated && !UIAccessibilityIsReduceMotionEnabled()) ? 0.25 : 0;
    [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ ed.alpha = 0; } completion:^(BOOL f) {
        [ed removeFromSuperview];
        [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ self->_content.alpha = ContentAlpha(MAX(0, MIN(1, self->_progress))); } completion:nil];
    }];
}

- (void)setQ:(CGFloat)q {
    _q = MAX(0, MIN(1, q));
    if (_q < 0.999 && _page != 0 && !_pageLink) _page = 0; // QQS always shows page 0
    [self layoutAll];
}

// QS fling: click 368 ms TOUCH_RESPONSE (0.3,0,0.1,1); otherwise FlingAnimationUtils
// (max 0.4 s) approximated with FAST_OUT_SLOW_IN and a velocity-based duration.
- (void)animateQTo:(CGFloat)target velocity:(CGFloat)v animated:(BOOL)animated {
    [_qLink invalidate];
    _qLink = nil;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) { [self setQ:target]; return; }
    _qFrom = _q;
    _qTo = target;
    CGFloat dist = fabs(target - _q) * ([self qsBottom] - [self qqsBottom]);
    _qDuration = v == 0 ? 0.368 : MAX(0.15, MIN(0.4, dist / MAX(1, fabs(v)) * 2.0));
    _qStartTime = CACurrentMediaTime();
    _qLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(qTick:)];
    [_qLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)qTick:(CADisplayLink *)l {
    CGFloat f = MIN(1, (CACurrentMediaTime() - _qStartTime) / _qDuration);
    CGFloat e = LQSCubic(0.3, 0, 0.1, 1, f);
    [self setQ:Lerp(_qFrom, _qTo, e)];
    if (f >= 1) { [_qLink invalidate]; _qLink = nil; _state = _qTo > 0.5 ? LQSPanelStateExpanded : LQSPanelStateCompact; }
}

#pragma mark - Presentation (native CC progress)

- (void)setPresentationProgress:(CGFloat)progress { [self setPresentationProgress:progress interactive:YES]; }

- (void)setPresentationProgress:(CGFloat)progress interactive:(BOOL)interactive {
    progress = MAX(0, MIN(1, progress));
    if (!interactive && _settleLink && fabs(progress - _settleTo) < 0.001) return;
    if (interactive || fabs(progress - _progress) < 0.001) {
        [_settleLink invalidate]; _settleLink = nil;
        [UIView performWithoutAnimation:^{ [self applyPresentationProgress:progress]; }];
        return;
    }
    _settleFrom = _progress;
    _settleTo = progress;
    _settleStart = CACurrentMediaTime();
    _settleDuration = UIAccessibilityIsReduceMotionEnabled() ? 0.12 : (progress > _progress ? 0.35 : 0.2 + 0.1 * _progress);
    if (progress > _progress && !UIAccessibilityIsReduceMotionEnabled()) {
        CAKeyframeAnimation *o = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        o.values = @[@0, @(16 * 0.6), @0];
        o.keyTimes = @[@0, @0.4, @1];
        o.timingFunctions = @[[CAMediaTimingFunction functionWithControlPoints:0.4 :0 :0.2 :1], [CAMediaTimingFunction functionWithControlPoints:0.4 :0 :0.2 :1]];
        o.duration = _settleDuration + 0.4;
        o.additive = YES;
        [_content.layer addAnimation:o forKey:@"overshoot"];
    }
    [_settleLink invalidate];
    _settleLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(settleTick:)];
    [_settleLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)settleTick:(CADisplayLink *)link {
    CGFloat f = MIN(1, (CACurrentMediaTime() - _settleStart) / _settleDuration);
    BOOL opening = _settleTo > _settleFrom;
    CGFloat e = opening ? LQSCubic(0.4, 0, 0.2, 1, f) : LQSCubic(0.3, 0, 0.5, 1, f);
    [UIView performWithoutAnimation:^{
        [self applyPresentationProgress:self->_settleFrom + (self->_settleTo - self->_settleFrom) * e];
    }];
    if (f >= 1) { [_settleLink invalidate]; _settleLink = nil; }
}

- (void)applyPresentationProgress:(CGFloat)progress {
    if (_progress <= 0.001 && progress > 0.001) { [self refreshRealStates]; [self startLiveUpdates]; }
    if (progress <= 0.001 && _progress > 0.001) { [self stopLiveUpdates]; [_dialog removeFromSuperview]; _dialog = nil; }
    _progress = progress;
    CGFloat p = MAX(0, MIN(1, progress));
    if ([self.delegate respondsToSelector:@selector(panel:didChangePresentationProgress:)])
        [self.delegate panel:self didChangePresentationProgress:p];
    // Panel background follows the expansion linearly (ScrimController behindAlpha * panelFraction).
    _backdrop.alpha = p;
    // The native presenter already reveals the shade. A second height mask
    // here cuts straight through quick tiles during opening and closing.
    // Keep the existing alpha/parallax and hide content at the closed endpoint.
    _content.hidden = p <= 0.001;
    _content.alpha = ContentAlpha(p);
    _content.transform = CGAffineTransformMakeTranslation(0, -0.175 * (1 - p) * [self qqsBottom]);
    if (p <= 0.001 && _editor) { [_editor removeFromSuperview]; _editor = nil; _state = LQSPanelStateExpanded; [self rebuildTiles]; }
    if (_editor) _content.alpha = 0;
    if (p <= 0.001 && _q > 0) { [_qLink invalidate]; _qLink = nil; _state = LQSPanelStateCompact; _page = 0; [self setQ:0]; }
    else [self layoutAll];
}

- (void)backdropTapped {
    if (_dialog.superview || _editor) return;
    [self.delegate panelRequestsDismiss:self];
}

#pragma mark - Gestures

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (_dialog.superview || _editor) return NO;
    if (g == _hpan) {
        if (_q < 0.999 || _pageCount < 2) return NO;
        CGPoint v = [_hpan velocityInView:self.view];
        return fabs(v.x) > fabs(v.y);
    }
    if (g == _vpan) {
        CGPoint v = [_vpan velocityInView:self.view], loc = [_vpan locationInView:_content];
        if (fabs(v.y) <= fabs(v.x)) return NO;
        if (CGRectContainsPoint(_brightness.frame, loc) && _q > 0.95 && fabs(v.x) > 0) return fabs(v.y) > 2 * fabs(v.x);
        // Inside the notification list the list's own pan handles it (listPan:).
        if (_q < 0.05 && !_notifs.hidden && CGRectContainsPoint(_notifs.frame, loc)) return NO;
        return YES;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return NO; }

// QS follows the finger 1:1 (QSC.onTouch: setExpansionHeight(h + initial)).
- (void)verticalPan:(UIPanGestureRecognizer *)g {
    CGFloat dy = [g translationInView:self.view].y, vy = [g velocityInView:self.view].y;
    CGFloat travel = MAX(100, [self qsBottom] - [self qqsBottom]);
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            [_qLink invalidate];
            _qLink = nil;
            _qStart = _q;
            break;
        case UIGestureRecognizerStateChanged:
            if (_qStart <= 0.001 && dy < 0) {
                // Collapsing from QQS closes the whole shade: follow the finger, the native CC
                // dismissal finishes it on release.
                [self applyPresentationProgress:MAX(0, 1 + dy / MAX(1, [self qqsBottom]))];
            } else {
                [self setQ:_qStart + dy / travel];
            }
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (_qStart <= 0.001 && dy < 0) {
                // Position threshold 56dp / velocity 125dp/s (DraggableHandler / SwipeDetector).
                if (-dy > 56 || vy < -125) [self.delegate panelRequestsDismiss:self];
                else [self setPresentationProgress:1 interactive:NO];
                break;
            }
            // flingExpandsQs: below the minimum velocity decide by position, else by direction.
            BOOL expand = fabs(vy) < 125 ? _q > 0.5 : vy > 0;
            [self animateQTo:expand ? 1 : 0 velocity:vy animated:YES];
            break;
        }
        default: break;
    }
}

- (UIView *)debugListView { return _notifs.scrollView; }

- (void)listPan:(UIPanGestureRecognizer *)g {
    UIScrollView *sv = _notifs.scrollView;
    CGFloat ty = [g translationInView:self.view].y, vy = [g velocityInView:self.view].y;
    CGFloat maxOff = MAX(0, sv.contentSize.height - sv.bounds.size.height);
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _listMode = 0;
            _listDecided = NO;
            [_qLink invalidate];
            _qLink = nil;
            break;
        case UIGestureRecognizerStateChanged: {
            if (!_listDecided && fabs(ty) > 2) {
                // Android: pulling down at the top of the list expands QS; pushing up when the
                // list is already at its end closes the shade. Reaching the end mid-scroll does not.
                _listDecided = YES;
                if (sv.contentOffset.y <= 0.5 && ty > 0 && _q < 0.05) { _listMode = 1; _listModeY = ty; _qStart = _q; }
                else if (sv.contentOffset.y >= maxOff - 0.5 && ty < 0 && _q < 0.05) { _listMode = 2; _listModeY = ty; }
            }
            if (_listMode == 1) {
                sv.contentOffset = CGPointZero; // no rubber band while the panel is expanding
                CGFloat travel = MAX(100, [self qsBottom] - [self qqsBottom]);
                [self setQ:_qStart + (ty - _listModeY) / travel];
            } else if (_listMode == 2) {
                sv.contentOffset = CGPointMake(0, maxOff);
                [self applyPresentationProgress:MAX(0, MIN(1, 1 + (ty - _listModeY) / MAX(1, [self qqsBottom])))];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (_listMode == 1) {
                BOOL expand = fabs(vy) < 125 ? _q > 0.5 : vy > 0;
                [self animateQTo:expand ? 1 : 0 velocity:vy animated:YES];
            } else if (_listMode == 2) {
                CGFloat dy = ty - _listModeY;
                if (-dy > 56 || vy < -125) [self.delegate panelRequestsDismiss:self];
                else [self setPresentationProgress:1 interactive:NO];
            }
            _listMode = 0;
            break;
        }
        default: break;
    }
}

- (void)pagePan:(UIPanGestureRecognizer *)g {
    CGFloat w = self.view.bounds.size.width, dx = [g translationInView:self.view].x, vx = [g velocityInView:self.view].x;
    switch (g.state) {
        case UIGestureRecognizerStateBegan: [_pageLink invalidate]; _pageLink = nil; _pageStart = _page; break;
        case UIGestureRecognizerStateChanged: {
            CGFloat p = _pageStart - dx / w;
            if (p < 0) p *= 0.3; else if (p > _pageCount - 1) p = (_pageCount - 1) + (p - (_pageCount - 1)) * 0.3; // edge resistance
            _page = p;
            [self layoutTilesOnly];
            _dots.position = MAX(0, MIN(_pageCount - 1, _page));
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat target = fabs(vx) > 300 ? (vx < 0 ? ceil(_page - 0.001) : floor(_page + 0.001)) : round(_page);
            target = MAX(0, MIN(_pageCount - 1, target));
            [self animatePageTo:target];
            break;
        }
        default: break;
    }
}

- (void)animatePageTo:(CGFloat)target {
    _pageFrom = _page;
    _pageTo = target;
    _pageStartTime = CACurrentMediaTime();
    [_pageLink invalidate];
    _pageLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(pageTick:)];
    [_pageLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)pageTick:(CADisplayLink *)l {
    CGFloat f = MIN(1, (CACurrentMediaTime() - _pageStartTime) / 0.3); // pager snap (assumption: 300 ms standard)
    _page = Lerp(_pageFrom, _pageTo, LQSCubic(0.4, 0, 0.2, 1, f));
    [self layoutTilesOnly];
    _dots.position = _page;
    if (f >= 1) { [_pageLink invalidate]; _pageLink = nil; }
}

@end
