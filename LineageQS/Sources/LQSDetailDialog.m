#import "LQSStrings.h"
#import "LQSDetailDialog.h"
#import "LQSTheme.h"
#import "LQSVectorIcon.h"
#import "LQSViews.h"
#import "LQSBackends.h"

// Dimensions: values/dimens.xml nt_dialog_* (docs/qs-detail-panels.md 2g, 3b).
static CGFloat D(CGFloat dp) { return [LQSTheme dp:dp]; }

#pragma mark - Android switch (NtSwitch, NTDialogSwitch style)
// Colours values-night: nt_switch_bg_checked ref_neutral_50, thumb ref_neutral_900,
// bg_unchecked ref_neutral_600. Geometry is not in the notes: 52x32dp track,
// 24dp thumb (assumption, Material-like).
@interface LQSSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@implementation LQSSwitch {
    UIView *_track, *_thumb;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _track = [UIView new]; _track.userInteractionEnabled = NO; [self addSubview:_track];
        _thumb = [UIView new]; _thumb.userInteractionEnabled = NO; [_track addSubview:_thumb];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self update];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(D(52), D(32)); }
- (void)tapped { LQSHapticTick(); [self setOn:!self.on animated:YES]; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    if (animated) [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ [self update]; [self layoutIfNeeded]; } completion:nil];
    else [self update];
    [self setNeedsLayout];
}
- (void)update {
    _track.backgroundColor = self.on ? LQSNeutral1(50) : LQSNeutral1(600);
    _thumb.backgroundColor = LQSNeutral1(900);
    self.accessibilityValue = self.on ? LQSL(@"On") : LQSL(@"Off");
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.intrinsicContentSize;
    _track.frame = CGRectMake(self.bounds.size.width - s.width, (self.bounds.size.height - s.height) / 2, s.width, s.height);
    _track.layer.cornerRadius = s.height / 2;
    CGFloat t = D(24), pad = (s.height - t) / 2;
    _thumb.frame = CGRectMake(self.on ? s.width - pad - t : pad, pad, t, t);
    _thumb.layer.cornerRadius = t / 2;
}
@end

#pragma mark - Row

@interface LQSDialogRow : UIControl
@property (nonatomic, strong) UIImageView *icon, *accessory, *accessory2;
@property (nonatomic, strong) UILabel *title, *summary;
@end

@implementation LQSDialogRow
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; _icon.tintColor = LQSNeutral1(50);
        _accessory = [UIImageView new]; _accessory.contentMode = UIViewContentModeCenter; _accessory.tintColor = LQSNeutral1(50);
        _accessory2 = [UIImageView new]; _accessory2.contentMode = UIViewContentModeCenter; _accessory2.tintColor = LQSNeutral2(200);
        _title = [UILabel new]; _title.font = [LQSTheme sansWithSize:D(16) weight:500]; _title.textColor = LQSNeutral1(50); // dialog_title_text_color
        _summary = [UILabel new]; _summary.font = [LQSTheme sansWithSize:D(12) weight:400]; _summary.textColor = LQSNeutral2(200); // dialog_sub_title_text_color
        for (UIView *v in @[_icon, _accessory, _accessory2, _title, _summary]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
        [self addTarget:self action:@selector(down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)down { [UIView animateWithDuration:0.1 animations:^{ self.alpha = 0.7; }]; }
- (void)up { [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1; }]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width, pad = D(18), is = D(24);
    BOOL hasIcon = self.icon.image != nil;
    self.icon.frame = CGRectMake(pad, (h - is) / 2, is, is);
    CGFloat x = hasIcon ? pad + is + D(16) : pad;
    CGFloat right = w - pad;
    if (self.accessory.image) { self.accessory.frame = CGRectMake(right - is, (h - is) / 2, is, is); right -= is + D(8); }
    if (self.accessory2.image) { self.accessory2.frame = CGRectMake(right - is, (h - is) / 2, is, is); right -= is + D(8); }
    BOOL two = self.summary.text.length > 0;
    CGFloat th = ceil(self.title.font.lineHeight), sh = ceil(self.summary.font.lineHeight) + D(2);
    CGFloat top = two ? (h - th - sh) / 2 : (h - th) / 2;
    self.title.frame = CGRectMake(x, top, right - x, th);
    self.summary.frame = CGRectMake(x, top + th + D(2), right - x, sh - D(2));
    self.accessibilityLabel = two ? [NSString stringWithFormat:@"%@, %@", self.title.text, self.summary.text] : self.title.text;
}
@end

#pragma mark - Dialog

@implementation LQSDetailDialog {
    UIView *_dim, *_card, *_footerLine;
    UILabel *_titleLabel, *_subtitle;
    UIActivityIndicatorView *_spinner;
    UIScrollView *_scroll;
    UIView *_toggleRow, *_toggleDivider;
    UILabel *_toggleTitle, *_toggleSummary;
    LQSSwitch *_switch;
    NSMutableArray<UIView *> *_rows;
    UIButton *_footer;
    NSArray *_networks;
    BOOL _scanning;
}

- (instancetype)initWithKind:(LQSDetailKind)kind {
    if ((self = [super initWithFrame:CGRectZero])) {
        _kind = kind;
        _rows = [NSMutableArray array];
        _dim = [UIView new];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; // dialog dim amount: assumption
        [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
        [self addSubview:_dim];
        _card = [UIView new];
        _card.backgroundColor = LQSNeutral1(900);          // nt_dialog_background_color
        _card.layer.cornerRadius = D(20);                   // nt_cust_dialog radius 20dp
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.clipsToBounds = YES;
        [self addSubview:_card];

        _titleLabel = [UILabel new];
        _titleLabel.text = kind == LQSDetailKindInternet ? LQSL(@"Internet") : LQSL(@"Connect"); // quick_settings_internet_label / bluetooth_device_context_connect
        _titleLabel.font = [LQSTheme sansWithSize:D(18) weight:500];                 // nt_dialog_text_size_18
        _titleLabel.textColor = LQSNeutral1(50);
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
        [_card addSubview:_titleLabel];
        _subtitle = [UILabel new];
        _subtitle.font = [LQSTheme sansWithSize:D(kind == LQSDetailKindInternet ? 12 : 14) weight:400];
        _subtitle.textColor = LQSNeutral2(200);
        _subtitle.textAlignment = NSTextAlignmentCenter;
        [_card addSubview:_subtitle];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = LQSNeutral1(50);
        _spinner.hidesWhenStopped = YES;
        [_card addSubview:_spinner];

        _scroll = [UIScrollView new];
        _scroll.alwaysBounceVertical = YES;
        [_card addSubview:_scroll];

        // Toggle row: turn_on_wifi_layout / bluetooth_toggle_lay (title 16sp 500, 1dp x 26dp divider, NtSwitch).
        _toggleRow = [UIView new];
        _toggleRow.backgroundColor = LQSNeutral1(800);      // nt_dialog_item_bg_color
        _toggleRow.layer.cornerRadius = D(20);
        [_scroll addSubview:_toggleRow];
        _toggleTitle = [UILabel new];
        _toggleTitle.text = kind == LQSDetailKindInternet ? LQSL(@"Wi‑Fi") : LQSL(@"Bluetooth"); // turn_on_wifi / quick_settings_bluetooth_label
        _toggleTitle.font = [LQSTheme sansWithSize:D(16) weight:500];
        _toggleTitle.textColor = LQSNeutral1(50);
        [_toggleRow addSubview:_toggleTitle];
        _toggleSummary = [UILabel new];
        _toggleSummary.font = [LQSTheme sansWithSize:D(12) weight:400];
        _toggleSummary.textColor = LQSNeutral2(200);
        [_toggleRow addSubview:_toggleSummary];
        _toggleDivider = [UIView new];
        _toggleDivider.backgroundColor = LQSNeutral1(700);  // nt_dialog_line_bg_color
        [_toggleRow addSubview:_toggleDivider];
        _switch = [LQSSwitch new];
        _switch.accessibilityLabel = _toggleTitle.text;
        [_switch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
        [_toggleRow addSubview:_switch];

        _footerLine = [UIView new];
        _footerLine.backgroundColor = LQSNeutral1(700);
        [_card addSubview:_footerLine];
        _footer = [UIButton buttonWithType:UIButtonTypeCustom];
        [_footer setTitle:(kind == LQSDetailKindInternet ? LQSL(@"Network settings") : LQSL(@"Bluetooth settings")) forState:UIControlStateNormal]; // wifi_tile_dialog_go_settings / bluetooth_tile_dialog_go_settings
        [_footer setTitleColor:LQSNeutral1(50) forState:UIControlStateNormal];
        _footer.titleLabel.font = [LQSTheme sansWithSize:D(16) weight:500];
        [_footer addTarget:self action:@selector(footerTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_footer];
        self.accessibilityViewIsModal = YES;
    }
    return self;
}

- (NSString *)tileId { return self.kind == LQSDetailKindInternet ? @"wifi" : @"bt"; }

- (void)presentInView:(UIView *)host {
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:self];
    [self reload];
    if (self.kind == LQSDetailKindInternet) [self startScan];
    [self layoutIfNeeded];
    // Launch animation unresolved in Android (SystemUIDialog default): fade + 0.95 scale, 250ms standard easing (assumption).
    _dim.alpha = 0; _card.alpha = 0; _card.transform = CGAffineTransformMakeScale(0.95, 0.95);
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.1 : 0.25
        timingParameters:[[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.4, 0) controlPoint2:CGPointMake(0.2, 1)]];
    [a addAnimations:^{ self->_dim.alpha = 1; self->_card.alpha = 1; self->_card.transform = CGAffineTransformIdentity; }];
    [a startAnimation];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _titleLabel);
}

- (void)dismiss {
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:0.18 curve:UIViewAnimationCurveEaseIn animations:^{
        self->_dim.alpha = 0; self->_card.alpha = 0; self->_card.transform = CGAffineTransformMakeScale(0.95, 0.95);
    }];
    [a addCompletion:^(UIViewAnimatingPosition p) { [self removeFromSuperview]; }];
    [a startAnimation];
}

- (void)startScan {
    if (_scanning || [LQSBackends stateFor:@"wifi"] != LQSBackendStateOn) return;
    _scanning = YES;
    [self reload];
    __weak typeof(self) weakSelf = self;
    [LQSBackends scanWiFiWithCompletion:^(NSArray *nets) {
        typeof(self) s = weakSelf;
        if (!s) return;
        s->_scanning = NO;
        s->_networks = nets;
        [s reload];
    }];
}

- (void)switchChanged {
    [LQSBackends setOn:_switch.on forIdentifier:[self tileId]];
    if (self.stateChanged) self.stateChanged();
    if (self.kind == LQSDetailKindInternet && _switch.on) {
        _networks = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self startScan]; });
    }
    for (NSNumber *d in @[@0.6, @1.5]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self reload]; });
}

- (void)footerTapped { LQSHapticTick(); if (self.openSettings) self.openSettings([self tileId]); }

- (LQSDialogRow *)rowWithTitle:(NSString *)t summary:(NSString *)s icon:(UIImage *)icon {
    LQSDialogRow *r = [LQSDialogRow new];
    r.title.text = t; r.summary.text = s; r.icon.image = icon;
    r.backgroundColor = LQSNeutral1(800);      // nt_dialog_item_bg (radius 20dp)
    r.layer.cornerRadius = D(20);
    return r;
}

- (void)reload {
    for (UIView *v in _rows) [v removeFromSuperview];
    [_rows removeAllObjects];
    BOOL on = [LQSBackends stateFor:[self tileId]] == LQSBackendStateOn;
    _switch.on = on;
    if (self.kind == LQSDetailKindInternet) {
        NSDictionary *info = [LQSBackends liveInfo];
        _toggleSummary.text = on ? ([info[@"wifiAssociated"] boolValue] ? info[@"wifiName"] : LQSL(@"Networks available")) : LQSL(@"Wi-Fi is off"); // wifi_is_off
        _subtitle.text = !on ? LQSL(@"Wi-Fi is off") : (_scanning && !_networks.count ? LQSL(@"Searching for networks…") : LQSL(@"Tap a network to connect")); // wifi_empty_list_wifi_on / tap_a_network_to_connect
        if (_scanning) [_spinner startAnimating]; else [_spinner stopAnimating];
        if (on) {
            for (NSDictionary *n in _networks) {
                NSString *icon = [NSString stringWithFormat:@"ic_wifi_%@", n[@"bars"]];
                BOOL current = [n[@"current"] boolValue];
                NSString *summary = current ? LQSL(@"Connected") : ([n[@"known"] boolValue] ? LQSL(@"Saved") : @""); // quick_settings_connected; "Saved" assumption
                LQSDialogRow *r = [self rowWithTitle:n[@"ssid"] summary:summary icon:[LQSVectorIcon imageNamed:icon side:D(24)]];
                if ([n[@"secure"] boolValue]) r.accessory2.image = [LQSVectorIcon imageNamed:@"qs_ic_wifi_lock" side:D(20)];
                if (current) {
                    r.accessory.image = [LQSVectorIcon imageNamed:@"ic_settings_24dp" side:D(24)];
                    r.backgroundColor = LQSNeutral1(700); // connected row highlighted (wifi_connected_layout; colour: assumption)
                }
                NSString *ssid = n[@"ssid"];
                BOOL known = [n[@"known"] boolValue];
                [r addAction:[UIAction actionWithHandler:^(UIAction *x) { [self networkTapped:ssid current:current known:known]; }] forControlEvents:UIControlEventTouchUpInside];
                [_scroll addSubview:r];
                [_rows addObject:r];
                if (_rows.count >= 50) break; // MAX_NETWORK_COUNT
            }
            LQSDialogRow *seeAll = [self rowWithTitle:LQSL(@"See all") summary:@"" icon:nil]; // see_all_networks
            seeAll.backgroundColor = UIColor.clearColor;
            seeAll.accessory.image = [LQSVectorIcon imageNamed:@"ic_arrow_forward_24dp" side:D(24)];
            [seeAll addAction:[UIAction actionWithHandler:^(UIAction *x) { [self footerTapped]; }] forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:seeAll];
            [_rows addObject:seeAll];
        }
    } else {
        _toggleSummary.text = on ? LQSL(@"On") : LQSL(@"Off");
        _subtitle.text = LQSL(@"Tap to connect or disconnect a device"); // quick_settings_bluetooth_tile_subtitle
        if (on) {
            for (NSDictionary *d in [LQSBackends bluetoothDevices]) {
                NSDictionary *iconFor = @{@"headphones": @"bluetooth_default_ear_icon", @"watch": @"ic_watch", @"phone": @"ic_phone_expressive", @"computer": @"ic_media_computer"};
                NSString *icon = iconFor[d[@"kind"]] ?: @"qs_bluetooth_icon_on";
                NSInteger bat = [d[@"battery"] integerValue];
                NSString *summary = [d[@"connected"] boolValue] ? (bat > 0 ? [NSString stringWithFormat:@"Connected, battery %ld%%", (long)bat] : LQSL(@"Connected")) : @""; // bluetooth_connected_battery_level
                LQSDialogRow *r = [self rowWithTitle:d[@"name"] summary:summary icon:[LQSVectorIcon imageNamed:icon side:D(36)]];
                NSString *addr = d[@"address"];
                BOOL connected = [d[@"connected"] boolValue];
                [r addAction:[UIAction actionWithHandler:^(UIAction *x) {
                    LQSHapticTick();
                    [LQSBackends setBluetoothDevice:addr connected:!connected];
                    [self->_spinner startAnimating];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_spinner stopAnimating]; [self reload]; }); // PROGRESS_BAR_ANIMATION_DURATION_MS
                }] forControlEvents:UIControlEventTouchUpInside];
                [_scroll addSubview:r];
                [_rows addObject:r];
            }
            LQSDialogRow *pair = [self rowWithTitle:LQSL(@"Pair new device") summary:@"" icon:[LQSVectorIcon imageNamed:@"ic_add" side:D(24)]]; // pair_new_bluetooth_devices
            pair.backgroundColor = UIColor.clearColor;
            [pair addAction:[UIAction actionWithHandler:^(UIAction *x) { [self footerTapped]; }] forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:pair];
            [_rows addObject:pair];
        }
    }
    [self setNeedsLayout];
}

- (void)networkTapped:(NSString *)ssid current:(BOOL)current known:(BOOL)known {
    LQSHapticTick();
    if (current || !known) {
        // Current network details or a new network that needs a password: iOS Settings.
        if (self.openSettings) self.openSettings(@"wifi");
        return;
    }
    if ([LQSBackends joinWiFi:ssid]) {
        _subtitle.text = [NSString stringWithFormat:LQSL(@"Connecting to %@…"), ssid]; // assumption
        for (NSNumber *d in @[@2.0, @4.0]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self->_networks = nil; [self startScan]; });
    } else if (self.openSettings) {
        self.openSettings(@"wifi");
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _dim.frame = b;
    CGFloat w = MIN(D(360), b.size.width - 2 * D(16));
    CGFloat maxH = MIN(D(584), b.size.height - 2 * D(40)); // nt_dialog_height 584dp
    CGFloat y = D(24);
    _titleLabel.frame = CGRectMake(D(24), y, w - 2 * D(24), ceil(_titleLabel.font.lineHeight));
    _spinner.center = CGPointMake(D(24) + 12, CGRectGetMidY(_titleLabel.frame));
    y = CGRectGetMaxY(_titleLabel.frame) + D(4);
    _subtitle.frame = CGRectMake(D(24), y, w - 2 * D(24), ceil(_subtitle.font.lineHeight));
    y = CGRectGetMaxY(_subtitle.frame) + D(16);
    CGFloat inset = D(14), rw = w - 2 * inset, ry = 0;
    CGFloat toggleH = D(72);
    _toggleRow.frame = CGRectMake(inset, ry, rw, toggleH);
    CGSize ss = _switch.intrinsicContentSize;
    _switch.frame = CGRectMake(rw - D(18) - ss.width, (toggleH - ss.height) / 2, ss.width, ss.height);
    _toggleDivider.frame = CGRectMake(CGRectGetMinX(_switch.frame) - D(16), (toggleH - D(26)) / 2, 1, D(26)); // nt_dialog_divider_height 26dp
    CGFloat th = ceil(_toggleTitle.font.lineHeight), sh = ceil(_toggleSummary.font.lineHeight);
    _toggleTitle.frame = CGRectMake(D(18), (toggleH - th - sh - D(2)) / 2, CGRectGetMinX(_toggleDivider.frame) - D(26), th);
    _toggleSummary.frame = CGRectMake(D(18), CGRectGetMaxY(_toggleTitle.frame) + D(2), _toggleTitle.frame.size.width, sh);
    ry = toggleH + D(12);
    for (UIView *r in _rows) {
        CGFloat h = self.kind == LQSDetailKindBluetooth && r.backgroundColor != UIColor.clearColor ? D(72) : D(64); // rows: 64dp see-all/pair; device/network rows 72dp (tile_details_entry_height)
        r.frame = CGRectMake(inset, ry, rw, h);
        ry += h + D(4);
    }
    CGFloat footerH = D(56);
    CGFloat contentH = ry + D(8);
    CGFloat cardH = MIN(maxH, y + contentH + 1 + footerH);
    _card.bounds = CGRectMake(0, 0, w, cardH);
    _card.center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    _scroll.frame = CGRectMake(0, y, w, cardH - y - 1 - footerH);
    _scroll.contentSize = CGSizeMake(w, contentH);
    _footerLine.frame = CGRectMake(D(32), cardH - footerH - 1, w - 2 * D(32), 1);
    _footer.frame = CGRectMake(0, cardH - footerH, w, footerH);
}

@end
