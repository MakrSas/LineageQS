#import "LQSStrings.h"
#import "LQSNotificationStack.h"
#import "LQSNotifications.h"
#import "LQSTheme.h"
#import "LQSModel.h"
#import "LQSViews.h"
#import "LQSVectorIcon.h"

// Android "now" / "5m" style stamps; iOS abbreviated formatter in the phone language.
static NSString *RelativeTime(NSDate *d) {
    if (!d) return @"";
    NSTimeInterval s = -[d timeIntervalSinceNow];
    if (s < 60) return LQSL(@"now");
    static NSDateComponentsFormatter *f;
    if (!f) {
        f = [NSDateComponentsFormatter new];
        f.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
        f.maximumUnitCount = 1;
        f.allowedUnits = NSCalendarUnitMinute | NSCalendarUnitHour | NSCalendarUnitDay | NSCalendarUnitWeekOfMonth;
    }
    return [f stringFromTimeInterval:s] ?: @"";
}

// Row background: surface container high, slightly translucent over the shade blur
// (assumption: exact notification background alpha under notification_shade_blur not resolved).
// Rows: lighter than the scrim (surfaceEffect1 @0.54 over it, assumption from Pixel screenshots).
static UIColor *RowColor(void) { return [LQSTheme surfaceEffect1]; }

static const CGFloat kMargin = 16;       // notification_2025_margin
static const CGFloat kIcon = 40;         // notification_2025_icon_circle_size
static const CGFloat kContentStart = 72; // notification_2025_content_margin_start
static const CGFloat kOuterRadius = 28;  // notification_corner_radius
static const CGFloat kInnerRadius = 4;   // notification_corner_radius_small
static const CGFloat kGap = 2;           // notification_divider_height

// Swipe haptics (NotificationSwipeHelper + MSDL SWIPE_THRESHOLD_INDICATOR): a tick
// when the drag crosses the dismiss threshold either way, a stronger one on dismiss.
static void SwipeHaptic(BOOL strong) {
    static UIImpactFeedbackGenerator *light, *medium;
    if (!light) { light = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; medium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]; }
    [(strong ? medium : light) impactOccurred];
}

// One app group (NotificationChildrenContainer): header with app icon, "App • time" and
// the expand pill (count + chevron, notification_2025_expand_button_pill 26x18dp);
// collapsed shows NUMBER_OF_CHILDREN_WHEN_COLLAPSED = 2 single-line children,
// expanded shows every child (up to NUMBER_OF_CHILDREN_WHEN_CHILDREN_EXPANDED = 8).
@interface LQSNotifRow : UIView
@property (nonatomic, copy) NSArray<LQSNotificationItem *> *items; // newest first
@property (nonatomic) BOOL expanded;
@property (nonatomic, copy) void (^onOpen)(LQSNotificationItem *item);
@property (nonatomic, copy) void (^onDismiss)(LQSNotifRow *row);
@property (nonatomic, copy) void (^onToggle)(LQSNotifRow *row);
- (CGFloat)heightForWidth:(CGFloat)w;
- (void)setTopRadius:(CGFloat)top bottomRadius:(CGFloat)bottom;
@end

@implementation LQSNotifRow {
    UIImageView *_icon;
    UILabel *_header;
    UIView *_pill;
    UILabel *_pillCount;
    UIImageView *_pillChevron;
    NSMutableArray<UIView *> *_children;
    CAShapeLayer *_shape;
    CGFloat _top, _bottom;
    UIPanGestureRecognizer *_swipe;
    BOOL _pastThreshold;
}

+ (UIFont *)titleFont { return [LQSTheme sansWithSize:16 weight:500]; }  // TextAppearance.Notification.Title (assumption 16sp Medium)
+ (UIFont *)textFont { return [LQSTheme sansWithSize:14 weight:400]; }   // TextAppearance.Notification 14sp
+ (UIFont *)headerFont { return [LQSTheme sansWithSize:12 weight:500]; } // header app name / time (assumption)

- (instancetype)initWithItems:(NSArray<LQSNotificationItem *> *)items expanded:(BOOL)expanded {
    if ((self = [super initWithFrame:CGRectZero])) {
        _items = [items copy];
        _expanded = expanded;
        LQSNotificationItem *it = items.firstObject;
        _shape = [CAShapeLayer layer];
        self.layer.mask = _shape;
        self.backgroundColor = RowColor();
        if ([LQSSettings current].blurSurfaces) {
            UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
            fx.userInteractionEnabled = NO;
            fx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self insertSubview:fx atIndex:0];
        }
        _icon = [[UIImageView alloc] initWithImage:it.icon];
        _icon.contentMode = UIViewContentModeScaleAspectFill;
        _icon.clipsToBounds = YES;
        _icon.layer.cornerRadius = kIcon / 2; // app icon in the 40dp circle
        _icon.backgroundColor = [LQSTheme primary];
        [self addSubview:_icon];
        _header = [UILabel new];
        _header.font = [LQSNotifRow headerFont];
        _header.textColor = [LQSTheme onSurfaceVariant];
        _header.text = [NSString stringWithFormat:@"%@ • %@", it.appName ?: it.bundleID, RelativeTime(it.date)];
        [self addSubview:_header];
        if (items.count > 1) {
            _pill = [UIView new];
            _pill.backgroundColor = LQSColor(@"surface_container_highest");
            _pill.layer.cornerRadius = 9;
            _pill.userInteractionEnabled = NO;
            _pillCount = [UILabel new];
            _pillCount.font = [LQSTheme sansWithSize:12 weight:500];
            _pillCount.textColor = [LQSTheme onSurface];
            _pillCount.text = [NSString stringWithFormat:@"%lu", (unsigned long)items.count];
            _pillChevron = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:@"ic_chevron_end" side:14]];
            _pillChevron.tintColor = [LQSTheme onSurface];
            _pillChevron.contentMode = UIViewContentModeCenter;
            _pillChevron.transform = CGAffineTransformMakeRotation(expanded ? -M_PI_2 : M_PI_2);
            [_pill addSubview:_pillCount];
            [_pill addSubview:_pillChevron];
            [self addSubview:_pill];
        }
        _children = [NSMutableArray array];
        NSUInteger shown = items.count == 1 ? 1 : (expanded ? MIN(8, items.count) : MIN(2, items.count));
        for (NSUInteger k = 0; k < shown; k++) {
            UIView *c = [self childFor:items[k] full:(items.count == 1 || expanded)];
            c.tag = 1000 + (NSInteger)k; // child index (subviews use tags 101-104)
            [c addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(childTapped:)]];
            [self addSubview:c];
            [_children addObject:c];
        }
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerTapped:)]];
        _swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        _swipe.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self addGestureRecognizer:_swipe];
        self.isAccessibilityElement = NO;
    }
    return self;
}

// Full child: title + up to 2 lines of text (+ attachment); single-line: "Title  text".
- (UIView *)childFor:(LQSNotificationItem *)it full:(BOOL)full {
    UIView *c = [UIView new];
    NSString *msg = it.subtitle.length ? [NSString stringWithFormat:@"%@\n%@", it.subtitle, it.message ?: @""] : (it.message ?: @"");
    if (full) {
        UILabel *t = [UILabel new]; t.tag = 101; t.font = [LQSNotifRow titleFont]; t.textColor = [LQSTheme onSurface]; t.text = it.title ?: it.appName;
        UILabel *m = [UILabel new]; m.tag = 102; m.font = [LQSNotifRow textFont]; m.textColor = [LQSTheme onSurfaceVariant]; m.numberOfLines = 2; m.text = msg;
        [c addSubview:t]; [c addSubview:m];
        if (it.attachment) {
            UIImageView *a = [[UIImageView alloc] initWithImage:it.attachment];
            a.tag = 103; a.contentMode = UIViewContentModeScaleAspectFill; a.clipsToBounds = YES; a.layer.cornerRadius = 8;
            [c addSubview:a];
        }
    } else {
        UILabel *l = [UILabel new]; l.tag = 104;
        NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:(it.title ?: it.appName ?: @"")
            attributes:@{NSFontAttributeName: [LQSTheme sansWithSize:14 weight:500], NSForegroundColorAttributeName: [LQSTheme onSurface]}];
        [a appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:[msg stringByReplacingOccurrencesOfString:@"\n" withString:@" "]]
            attributes:@{NSFontAttributeName: [LQSNotifRow textFont], NSForegroundColorAttributeName: [LQSTheme onSurfaceVariant]}]];
        l.attributedText = a;
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        [c addSubview:l];
    }
    c.isAccessibilityElement = YES;
    c.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", it.appName ?: @"", it.title ?: @"", it.message ?: @""];
    c.accessibilityTraits = UIAccessibilityTraitButton;
    return c;
}

+ (CGFloat)fullChildHeight:(LQSNotificationItem *)it width:(CGFloat)textW {
    NSString *msg = it.subtitle.length ? [NSString stringWithFormat:@"%@\n%@", it.subtitle, it.message ?: @""] : (it.message ?: @"");
    UIFont *tf = [self textFont];
    CGFloat w = MAX(10, textW - (it.attachment ? 60 : 0));
    CGFloat mh = msg.length ? MIN(ceil(tf.lineHeight) * 2, ceil([msg boundingRectWithSize:CGSizeMake(w, 999) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: tf} context:nil].size.height)) : 0;
    return ceil([self titleFont].lineHeight) + (mh ? 2 + mh : 0);
}

- (BOOL)single { return self.items.count == 1; }

- (CGFloat)heightForWidth:(CGFloat)w {
    CGFloat textW = w - kContentStart - kMargin;
    CGFloat h = kMargin + 18; // header line
    if ([self single] || self.expanded) {
        for (NSUInteger k = 0; k < _children.count; k++) h += (k ? 12 : 0) + [LQSNotifRow fullChildHeight:self.items[k] width:textW];
    } else {
        h += 4 + _children.count * 22; // single-line children (assumption: 22dp rows)
    }
    return MAX(72, h + kMargin); // notification_2025_min_height (assumption 72dp)
}

- (void)setTopRadius:(CGFloat)top bottomRadius:(CGFloat)bottom { _top = top; _bottom = bottom; [self setNeedsLayout]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat t = _top, b = _bottom;
    [p moveToPoint:CGPointMake(t, 0)];
    [p addLineToPoint:CGPointMake(w - t, 0)];
    [p addArcWithCenter:CGPointMake(w - t, t) radius:t startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(w, h - b)];
    [p addArcWithCenter:CGPointMake(w - b, h - b) radius:b startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(b, h)];
    [p addArcWithCenter:CGPointMake(b, h - b) radius:b startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(0, t)];
    [p addArcWithCenter:CGPointMake(t, t) radius:t startAngle:M_PI endAngle:1.5 * M_PI clockwise:YES];
    [p closePath];
    _shape.frame = self.bounds;
    _shape.path = p.CGPath;
    _icon.frame = CGRectMake(kMargin, kMargin, kIcon, kIcon);
    CGFloat right = w - kMargin, x = kContentStart, y = kMargin;
    if (_pill) {
        CGSize cs = [_pillCount sizeThatFits:CGSizeMake(40, 18)];
        CGFloat pw = MAX(26, 8 + cs.width + 2 + 14 + 4);
        _pill.frame = CGRectMake(right - pw, y - 1, pw, 18);
        _pillCount.frame = CGRectMake(8, 0, cs.width, 18);
        _pillChevron.bounds = CGRectMake(0, 0, 14, 14);
        _pillChevron.center = CGPointMake(pw - 4 - 7, 9);
        right -= pw + 8;
    }
    _header.frame = CGRectMake(x, y, right - x, 16);
    y += 18;
    CGFloat fullRight = w - kMargin;
    BOOL full = [self single] || self.expanded;
    if (!full) y += 4;
    for (NSUInteger k = 0; k < _children.count; k++) {
        UIView *c = _children[k];
        if (full) {
            if (k) y += 12;
            CGFloat ch = [LQSNotifRow fullChildHeight:self.items[k] width:fullRight - x];
            c.frame = CGRectMake(x, y, fullRight - x, ch);
            UIView *a = [c viewWithTag:103];
            CGFloat tr = c.bounds.size.width - (a ? 60 : 0);
            if (a) a.frame = CGRectMake(c.bounds.size.width - 48, 0, 48, 48);
            UILabel *tl = (UILabel *)[c viewWithTag:101], *ml = (UILabel *)[c viewWithTag:102];
            tl.frame = CGRectMake(0, 0, tr, ceil(tl.font.lineHeight));
            ml.frame = CGRectMake(0, CGRectGetMaxY(tl.frame) + 2, tr, MAX(0, ch - CGRectGetMaxY(tl.frame) - 2));
            y += ch;
        } else {
            c.frame = CGRectMake(x, y, fullRight - x, 22);
            [c viewWithTag:104].frame = c.bounds;
            y += 22;
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; self.backgroundColor = RowColor(); }

- (void)childTapped:(UITapGestureRecognizer *)g {
    if (![self single] && !self.expanded) { [self headerTapped:nil]; return; } // collapsed group: tap expands
    NSUInteger k = (NSUInteger)(g.view.tag - 1000);
    if (k < self.items.count && self.onOpen) self.onOpen(self.items[k]);
}
- (void)headerTapped:(UITapGestureRecognizer *)g {
    if ([self single]) { if (self.onOpen) self.onOpen(self.items.firstObject); return; }
    LQSHapticTick();
    if (self.onToggle) self.onToggle(self);
}

// UIView asks the hit view about every recognizer up the chain (including the list's
// scroll pan): only judge our own swipe recognizer.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g != _swipe) return YES;
    CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
    return fabs(v.x) > fabs(v.y); // horizontal swipe only
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGFloat tx = [g translationInView:self.superview].x, w = self.bounds.size.width;
    CGFloat threshold = w * 0.5; // NotificationSwipeHelper dismiss fraction (assumption: 0.5)
    if (g.state == UIGestureRecognizerStateBegan) _pastThreshold = NO;
    if (g.state == UIGestureRecognizerStateChanged) {
        self.transform = CGAffineTransformMakeTranslation(tx, 0);
        BOOL past = fabs(tx) > threshold;
        if (past != _pastThreshold) { _pastThreshold = past; SwipeHaptic(NO); }
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat vx = [g velocityInView:self.superview].x;
        if (fabs(tx) > threshold || fabs(vx) > 1000) {
            CGFloat dir = (tx + vx * 0.1) >= 0 ? 1 : -1;
            SwipeHaptic(YES);
            [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.transform = CGAffineTransformMakeTranslation(dir * w * 1.2, 0);
            } completion:^(BOOL f) { if (self.onDismiss) self.onDismiss(self); }];
        } else {
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
        }
    }
}

@end

@implementation LQSNotificationStack {
    UIScrollView *_scroll;
    NSMutableArray<LQSNotifRow *> *_rows;
    NSMutableSet<NSString *> *_expandedGroups;
    UIButton *_manage, *_clear;
    UILabel *_empty;
    UIView *_scrimBg;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        // ShadeColors.classicShadeNotificationScrimBg: customColorSurfaceEffect0 (monet opacity
        // 0.5, CustomDynamicColors.java:344-351) over the shade panel; rounded top (28dp, assumption).
        _scrimBg = [UIView new];
        _scrimBg.userInteractionEnabled = NO;
        _scrimBg.layer.cornerRadius = 28;
        _scrimBg.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _scrimBg.backgroundColor = [LQSColor(@"surface_effect_0") colorWithAlphaComponent:0.5];
        _scroll = [UIScrollView new];
        _scroll.alwaysBounceVertical = YES;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.clipsToBounds = YES;
        [self addSubview:_scroll];
        [_scroll insertSubview:_scrimBg atIndex:0]; // scrolls with the rows
        _rows = [NSMutableArray array];
        _expandedGroups = [NSMutableSet set];
        _manage = [self pill:LQSL(@"Manage") action:@selector(manageTapped)];
        _clear = [self pill:LQSL(@"Clear all") action:@selector(clearAllTapped)];
        _empty = [UILabel new];
        _empty.text = LQSL(@"No notifications"); // empty_shade_text
        _empty.font = [LQSTheme sansWithSize:16 weight:400];
        _empty.textColor = [LQSTheme onSurfaceVariant];
        _empty.textAlignment = NSTextAlignmentCenter;
        [_scroll addSubview:_empty];
        __weak typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:LQSNotificationsChangedNotification object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) { [weakSelf reload]; }];
    }
    return self;
}

- (UIScrollView *)scrollView { return _scroll; }

// FooterView: pill buttons, 40dp high (assumption), surface container high, onSurface text.
- (UIButton *)pill:(NSString *)title action:(SEL)sel {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 0, 16);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [LQSTheme sansWithSize:14 weight:500], NSForegroundColorAttributeName: [LQSTheme onSurface]}];
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.backgroundColor = RowColor();
    b.layer.cornerRadius = 20;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:b];
    return b;
}

- (void)reload {
    NSMutableDictionary<NSString *, NSValue *> *old = [NSMutableDictionary dictionary];
    for (LQSNotifRow *r in _rows) if (r.items.count && CGAffineTransformIsIdentity(r.transform)) old[r.items.firstObject.bundleID] = [NSValue valueWithCGRect:r.frame];
    BOOL hadRows = _rows.count > 0;
    for (UIView *v in _rows) [v removeFromSuperview];
    [_rows removeAllObjects];
    // Group by app (Android groups by group key; iOS thread ids are finer: assumption).
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    for (LQSNotificationItem *it in [LQSNotifications shared].items) {
        if (!groups[it.bundleID]) { groups[it.bundleID] = [NSMutableArray array]; [order addObject:it.bundleID]; }
        [groups[it.bundleID] addObject:it];
    }
    __weak typeof(self) weakSelf = self;
    for (NSString *key in order) {
        LQSNotifRow *r = [[LQSNotifRow alloc] initWithItems:groups[key] expanded:[_expandedGroups containsObject:key]];
        r.onOpen = ^(LQSNotificationItem *item) {
            LQSHapticTick();
            [[LQSNotifications shared] openItem:item];
            if (weakSelf.requestDismiss) weakSelf.requestDismiss();
        };
        r.onDismiss = ^(LQSNotifRow *row) { [[LQSNotifications shared] clearItems:row.items]; };
        r.onToggle = ^(LQSNotifRow *row) {
            typeof(self) s = weakSelf;
            if ([s->_expandedGroups containsObject:key]) [s->_expandedGroups removeObject:key]; else [s->_expandedGroups addObject:key];
            // New rows must not animate from a zero frame: rebuild and lay out, then cross-fade.
            [UIView transitionWithView:s->_scroll duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{ [UIView performWithoutAnimation:^{ [s reload]; [s layoutIfNeeded]; }]; } completion:nil];
        };
        [_scroll insertSubview:r atIndex:1];
        [_rows addObject:r];
        NSValue *f = old[key];
        if (f) r.frame = f.CGRectValue;
        else if (hadRows && self.window) { r.alpha = 0; r.transform = CGAffineTransformMakeScale(0.96, 0.96); } // new notification
    }
    if (!self.window || !old.count) { [self setNeedsLayout]; return; }
    // Remaining rows close the gap, footer and empty text cross over (spring, no bounce).
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (LQSNotifRow *r in self->_rows) { r.alpha = 1; r.transform = CGAffineTransformIdentity; }
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
}

- (CGFloat)contentHeight { [self layoutIfNeeded]; return _scroll.contentSize.height; }

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    self.clipsToBounds = NO;
    CGFloat w = self.bounds.size.width - 2 * kMargin, y = kMargin + 8; // first row: same visual gap as the side margin
    for (NSUInteger i = 0; i < _rows.count; i++) {
        LQSNotifRow *r = _rows[i];
        CGFloat h = [r heightForWidth:w];
        if (CGAffineTransformIsIdentity(r.transform)) r.frame = CGRectMake(kMargin, y, w, h);
        else r.bounds = CGRectMake(0, 0, w, h);
        // One section: outer 28dp at the ends, 4dp between rows, 2dp dividers.
        [r setTopRadius:(i == 0 ? kOuterRadius : kInnerRadius) bottomRadius:(i == _rows.count - 1 ? kOuterRadius : kInnerRadius)];
        y += h + kGap;
    }
    BOOL none = _rows.count == 0;
    _empty.hidden = NO; _manage.hidden = NO; _clear.hidden = NO;
    _empty.alpha = none ? 1 : 0;
    _manage.alpha = _clear.alpha = none ? 0 : 1;
    _manage.transform = _clear.transform = none ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
    _manage.userInteractionEnabled = _clear.userInteractionEnabled = !none;
    if (none) {
        _empty.frame = CGRectMake(kMargin, y + 8, w, 24);
        y += 56;
    } else {
        y += 16 - kGap; // footer margin (assumption)
        CGSize ms = [_manage sizeThatFits:CGSizeMake(200, 40)], cs = [_clear sizeThatFits:CGSizeMake(200, 40)];
        _manage.frame = CGRectMake(kMargin, y, ms.width, 40);
        _clear.frame = CGRectMake(kMargin + w - cs.width, y, cs.width, 40);
        y += 40 + 32; // notification_panel_margin_bottom 32dp
    }
    _scroll.contentSize = CGSizeMake(self.bounds.size.width, y);
    _scrimBg.hidden = NO; // the scrim spans the whole stack, including the empty-shade text
    _scrimBg.frame = CGRectMake(0, 0, self.bounds.size.width, MAX(y, self.bounds.size.height) + 800); // 16dp above the first row
    [_scroll sendSubviewToBack:_scrimBg];
}

- (void)clearAllTapped {
    LQSHapticTick();
    NSArray *all = [LQSNotifications shared].items;
    [_rows enumerateObjectsUsingBlock:^(LQSNotifRow *r, NSUInteger i, BOOL *stop) {
        // Bottom-up stagger like Android's clear-all (NotificationStackScrollLayout: 60ms per row, assumption).
        NSUInteger k = self->_rows.count - 1 - i;
        [UIView animateWithDuration:0.25 delay:k * 0.05 options:UIViewAnimationOptionCurveEaseIn animations:^{ r.transform = CGAffineTransformMakeTranslation(r.bounds.size.width * 1.1, 0); r.alpha = 0; } completion:nil];
    }];
    [UIView animateWithDuration:0.25 delay:0.1 options:0 animations:^{ self->_manage.alpha = self->_clear.alpha = 0; self->_manage.transform = self->_clear.transform = CGAffineTransformMakeScale(0.85, 0.85); } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.25 + _rows.count * 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[LQSNotifications shared] clearItems:all];
    });
}

- (void)manageTapped { LQSHapticTick(); if (self.openSettingsURL) self.openSettingsURL(@"prefs:root=NOTIFICATIONS_ID"); }

@end
