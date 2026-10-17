#import "LQSStrings.h"
#import "LQSViews.h"
#import "LQSTheme.h"
#import "LQSVectorIcon.h"

void LQSHapticTick(void) {
    if (![LQSSettings current].haptics) return;
    // Generic iOS tick; the MSDL tile haptics of Android 17 are not reproduced.
    static UIImpactFeedbackGenerator *gen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; });
    [gen impactOccurred];
}

CGFloat LQSCubic(double x1, double y1, double x2, double y2, double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    double t = x;
    for (int i = 0; i < 8; i++) {
        double xt = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t;
        double dx = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2);
        if (fabs(dx) < 1e-6) break;
        t = MAX(0, MIN(1, t - (xt - x) / dx));
    }
    return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t;
}

// Compose spring() default: dampingRatio 1 (no bounce), stiffness 1500 (StiffnessMedium).
static UIViewPropertyAnimator *DefaultSpring(void) {
    UISpringTimingParameters *p = [[UISpringTimingParameters alloc] initWithMass:1 stiffness:1500 damping:2 * sqrt(1500) initialVelocity:CGVectorMake(0, 0)];
    return [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:p];
}

#pragma mark - Tile

typedef struct {
    __unsafe_unretained UIColor *background, *iconBackground, *label, *secondary, *icon;
} LQSTileColors;

@implementation LQSTileView {
    UIView *_body, *_overlay, *_bubble, *_textBox;
    UIImageView *_icon;
    UILabel *_title, *_state;
    CAGradientLayer *_titleFade, *_stateFade;
    CADisplayLink *_iconLink;
    CFTimeInterval _iconStart;
    NSString *_animIcon;
    // Strong copies of the current colours (the struct above is unretained).
    UIColor *_cBg, *_cIconBg, *_cLabel, *_cSecondary, *_cIcon;
}

- (instancetype)initWithSpec:(LQSTileSpec *)spec size:(LQSTileSize)size {
    if ((self = [super initWithFrame:CGRectZero])) {
        _spec = spec;
        _size = size;
        _squish = 1;
        self.clipsToBounds = NO;
        _body = [UIView new];
        _body.userInteractionEnabled = NO;
        _body.clipsToBounds = YES;
        [self addSubview:_body];
        if ([LQSSettings current].blurSurfaces) {
            UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
            fx.userInteractionEnabled = NO;
            fx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            fx.tag = 77;
            fx.clipsToBounds = YES;
            [self insertSubview:fx atIndex:0]; // behind the tile colour: active tiles stay opaque primary
        }
        _overlay = [UIView new]; // InteractionsConfig pressed overlay: onSurface @ 0.15
        _overlay.alpha = 0;
        _overlay.userInteractionEnabled = NO;
        [_body addSubview:_overlay];
        _bubble = [UIView new];
        _bubble.userInteractionEnabled = NO;
        [_body addSubview:_bubble];
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeCenter;
        [_body addSubview:_icon];
        _textBox = [UIView new];
        _textBox.userInteractionEnabled = NO;
        [_body addSubview:_textBox];
        _title = [UILabel new];
        _title.font = [LQSTheme tileLabelFont];
        _title.lineBreakMode = NSLineBreakByClipping;
        [_textBox addSubview:_title];
        _state = [UILabel new];
        _state.font = [LQSTheme tileSecondaryFont];
        _state.lineBreakMode = NSLineBreakByClipping;
        [_textBox addSubview:_state];
        [self addTarget:self action:@selector(pressDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(pressUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyColors:NO];
    }
    return self;
}

- (BOOL)bouncesContainer { return self.spec.toggleable && (self.size == LQSTileSizeSmall || !self.spec.dualTarget); }

// TileDefaults.getColorForState (Tile.kt:529-584).
- (void)resolveColors {
    BOOL large = self.size == LQSTileSizeLarge, dual = self.spec.dualTarget;
    if (self.unavailable) {
        UIColor *bg = [[LQSTheme surface] colorWithAlphaComponent:0.18], *fg = [[LQSTheme onSurfaceVariant] colorWithAlphaComponent:0.38];
        _cBg = bg; _cIconBg = bg; _cLabel = _cSecondary = _cIcon = fg;
    } else if (self.on) {
        if (large && dual) { _cBg = [LQSTheme surfaceEffect1]; _cIconBg = [LQSTheme primary]; _cLabel = _cSecondary = [LQSTheme onSurface]; _cIcon = [LQSTheme onPrimary]; }
        else { _cBg = _cIconBg = [LQSTheme primary]; _cLabel = _cSecondary = _cIcon = [LQSTheme onPrimary]; }
    } else {
        _cBg = [LQSTheme surfaceEffect1];
        _cIconBg = (large && dual) ? [LQSTheme surfaceEffect2] : UIColor.clearColor;
        _cLabel = _cSecondary = _cIcon = [LQSTheme onSurface];
    }
}

- (NSString *)currentIconName { return self.iconOverride ?: (self.on ? self.spec.iconOn : self.spec.iconOff); }
- (CGFloat)iconSide { return self.size == LQSTileSizeSmall ? [LQSTheme iconSide] : [LQSTheme largeIconSide]; }

- (NSString *)currentStateText {
    if (self.unavailable) return LQSL(@"tile_unavailable");
    if (self.stateText) return self.stateText;
    return self.spec.toggleable ? LQSL(self.on ? @"On" : @"Off") : @"";
}

- (void)applyColors:(BOOL)animated {
    [self resolveColors];
    BOOL active = self.on && !self.unavailable;
    CGFloat radius = active ? [LQSTheme radiusActive] : [LQSTheme radiusInactive];
    CGFloat bubbleRadius = active ? [LQSTheme iconRadiusActive] : [LQSTheme toggleTarget] / 2;
    UIImage *img = [LQSVectorIcon imageNamed:[self currentIconName] side:[self iconSide]];
    NSString *text = [self currentStateText];
    void (^shape)(void) = ^{
        self->_body.backgroundColor = self->_cBg;
        self->_body.layer.cornerRadius = MIN(radius, self.bounds.size.height / 2);
        [self viewWithTag:77].layer.cornerRadius = self->_body.layer.cornerRadius;
        self->_bubble.backgroundColor = self->_cIconBg;
        self->_bubble.layer.cornerRadius = bubbleRadius;
    };
    if (animated && self.window && !UIAccessibilityIsReduceMotionEnabled()) {
        UIViewPropertyAnimator *a = DefaultSpring(); // animateColorAsState / animateDpAsState defaults
        [a addAnimations:shape];
        [a startAnimation];
        UIViewAnimationOptions o = UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
        if (!_iconLink) [UIView transitionWithView:_icon duration:0.25 options:o animations:^{ self->_icon.image = img; self->_icon.tintColor = self->_cIcon; } completion:nil];
        else _icon.tintColor = _cIcon;
        [UIView transitionWithView:_textBox duration:0.25 options:o animations:^{
            self->_title.textColor = self->_cLabel;
            self->_state.textColor = self->_cSecondary;
            self->_state.text = text;
        } completion:nil];
    } else {
        shape();
        _icon.image = img;
        _icon.tintColor = _cIcon;
        _title.textColor = _cLabel;
        _state.textColor = _cSecondary;
        _state.text = text;
    }
    _overlay.backgroundColor = [[LQSTheme onSurface] colorWithAlphaComponent:0.15];
    _title.text = self.spec.title;
    self.accessibilityLabel = self.spec.title;
    self.accessibilityValue = text.length ? text : nil;
    [self setNeedsLayout];
}

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (on == _on) return; // repeated readbacks must not restart animations
    _on = on;
    if (animated) _stateText = nil; // owner re-reads the live label
    [self applyColors:animated];
    // AnimatedVectorDrawable: skipped on first appearance, played on state change
    // (CommonTile.kt:264-278).
    if (!animated || UIAccessibilityIsReduceMotionEnabled() || self.iconOverride) return;
    NSString *icon = on ? self.spec.iconOn : self.spec.iconOff;
    if ([LQSVectorIcon animationDurationNamed:icon] <= 0) return;
    _animIcon = icon;
    _iconStart = CACurrentMediaTime();
    [_iconLink invalidate];
    _iconLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(iconTick:)];
    [_iconLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self iconTick:_iconLink];
}

- (void)iconTick:(CADisplayLink *)link {
    NSTimeInterval dur = [LQSVectorIcon animationDurationNamed:_animIcon], t = CACurrentMediaTime() - _iconStart;
    if (t >= dur || !self.window) {
        [_iconLink invalidate];
        _iconLink = nil;
        _icon.image = [LQSVectorIcon imageNamed:[self currentIconName] side:[self iconSide]];
        return;
    }
    UIImage *frame = [LQSVectorIcon frameNamed:_animIcon side:[self iconSide] atTime:t];
    if (frame) _icon.image = frame;
}

- (void)setUnavailable:(BOOL)u { if (u == _unavailable) return; _unavailable = u; [self applyColors:YES]; }
- (void)setSize:(LQSTileSize)size { if (size == _size) return; _size = size; [self applyColors:NO]; }
- (void)setIconOverride:(NSString *)name {
    if ((name == nil && _iconOverride == nil) || [name isEqualToString:_iconOverride]) return;
    _iconOverride = [name copy];
    if (!_iconLink) _icon.image = [LQSVectorIcon imageNamed:[self currentIconName] side:[self iconSide]];
}
- (void)setSquish:(CGFloat)s { _squish = MAX(0.1, MIN(1, s)); }

- (void)setStateText:(NSString *)t {
    if ((t == nil && _stateText == nil) || [t isEqualToString:_stateText]) return;
    _stateText = [t copy];
    NSString *text = [self currentStateText];
    if ([text isEqualToString:_state.text]) return;
    if (self.window && self.size == LQSTileSizeLarge && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:_state duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ self->_state.text = text; } completion:nil];
    } else {
        _state.text = text;
    }
    self.accessibilityValue = text;
    [self setNeedsLayout];
}

// TileLabel: one line, end fades over 32dp when the text overflows (CommonTile.kt:334-358).
static void Fade(UILabel *l, CAGradientLayer *__strong *mask) {
    CGFloat need = [l.text sizeWithAttributes:@{NSFontAttributeName: l.font}].width, w = l.bounds.size.width;
    if (need <= w + 0.5 || w <= 0) { l.layer.mask = nil; return; }
    if (!*mask) {
        *mask = [CAGradientLayer layer];
        (*mask).startPoint = CGPointMake(0, 0.5);
        (*mask).endPoint = CGPointMake(1, 0.5);
        (*mask).colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    }
    (*mask).frame = l.bounds;
    (*mask).locations = @[@0, @(MAX(0, (w - 32) / w)), @1];
    l.layer.mask = *mask;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _body.frame = self.bounds;
    _overlay.frame = _body.bounds;
    UIView *fx = [self viewWithTag:77];
    fx.frame = self.bounds;
    fx.layer.cornerRadius = _body.layer.cornerRadius;
    BOOL active = self.on && !self.unavailable;
    _body.layer.cornerRadius = MIN(active ? [LQSTheme radiusActive] : [LQSTheme radiusInactive], h / 2);
    CGFloat full = [LQSTheme tileHeight]; // content keeps its size and stays centred while squished
    if (self.size == LQSTileSizeSmall) {
        _bubble.hidden = YES;
        _textBox.hidden = YES;
        _icon.bounds = CGRectMake(0, 0, [LQSTheme iconSide], [LQSTheme iconSide]);
        _icon.center = CGPointMake(w / 2, h / 2);
    } else {
        _bubble.hidden = NO;
        _textBox.hidden = NO;
        CGFloat t = [LQSTheme toggleTarget], pad = 8; // StartPadding 8dp, ToggleTargetSize 56dp
        _bubble.frame = CGRectMake(pad, (h - t * self.squish) / 2, t, t * self.squish);
        _icon.bounds = CGRectMake(0, 0, [LQSTheme largeIconSide], [LQSTheme largeIconSide]);
        _icon.center = CGPointMake(pad + t / 2, h / 2);
        CGFloat x = pad + t + 6, end = 12; // TileArrangementPadding 6dp, TileEndPadding 12dp
        BOOL two = _state.text.length > 0;
        CGFloat lh = 20, sh = 16; // line heights 20sp / 16sp
        CGFloat total = lh + (two ? sh : 0);
        _textBox.frame = CGRectMake(x, (h - total) / 2, MAX(0, w - x - end), total);
        _title.frame = CGRectMake(0, 0, _textBox.bounds.size.width, lh);
        _state.frame = CGRectMake(0, lh, _textBox.bounds.size.width, sh);
        _state.hidden = !two;
        Fade(_title, &_titleFade);
        Fade(_state, &_stateFade);
    }
    (void)full;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint p = [touch locationInView:self];
    _lastTouchInIcon = self.size == LQSTileSizeSmall || CGRectContainsPoint(CGRectInset(_bubble.frame, -4, -4), p);
    return [super beginTrackingWithTouch:touch withEvent:event];
}

- (void)pressDown {
    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ self->_overlay.alpha = 1; } completion:nil];
    if (self.onPress && self.bouncesContainer) self.onPress(self, YES);
}
- (void)pressUp {
    [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ self->_overlay.alpha = 0; } completion:nil];
    if (self.onPress && self.bouncesContainer) self.onPress(self, NO);
}

// Content bounce: keyframes 1 -> scale at 167 ms (CubicBezier(.05,0,0,1)) -> 1 at
// 334 ms (CubicBezier(1,0,.95,1)). Icon x1.10 (centre), text x1.06 (start, centre-y).
- (void)contentBounce {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    void (^bounce)(CALayer *, CGFloat) = ^(CALayer *layer, CGFloat scale) {
        CAKeyframeAnimation *k = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        k.values = @[@1, @(scale), @1];
        k.keyTimes = @[@0, @0.5, @1];
        k.timingFunctions = @[[CAMediaTimingFunction functionWithControlPoints:0.05 :0 :0 :1], [CAMediaTimingFunction functionWithControlPoints:1 :0 :0.95 :1]];
        k.duration = 0.334;
        [layer addAnimation:k forKey:@"bounce"];
    };
    if (self.size == LQSTileSizeSmall) { bounce(_icon.layer, 1.10); return; }
    CGRect f = _textBox.frame;
    _textBox.layer.anchorPoint = CGPointMake(0, 0.5);
    _textBox.frame = f;
    bounce(_textBox.layer, 1.06);
}

@end

#pragma mark - Brightness

// BrightnessSliderDimensions.Default (BrightnessSlider.kt:581-599): track 40dp,
// thumb 4x52dp, track corners 12dp (2dp at the thumb), 6dp gap around the thumb,
// icon 28dp inset 6dp; auto button 52dp circle after a 10dp spacer.
@implementation LQSBrightnessView {
    UIView *_active, *_inactive, *_thumb;
    UIImageView *_iconView;
    UIButton *_auto;
    CGFloat _startValue;
    UIPanGestureRecognizer *_drag;
    UITapGestureRecognizer *_tapper;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _active = [UIView new];
        _inactive = [UIView new];
        _thumb = [UIView new];
        for (UIView *v in @[_inactive, _active, _thumb]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeCenter;
        [self addSubview:_iconView];
        _auto = [UIButton buttonWithType:UIButtonTypeCustom];
        _auto.layer.cornerRadius = 26;
        _auto.accessibilityLabel = LQSL(@"Auto brightness");
        [_auto addTarget:self action:@selector(autoTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_auto];
        _showAuto = YES;
        _value = 0.5;
        _drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:_drag];
        _tapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        [self addGestureRecognizer:_tapper];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.accessibilityLabel = LQSL(@"brightness_slider_description");
        [self applyColors];
    }
    return self;
}

- (void)applyColors {
    _active.backgroundColor = [LQSTheme primary];
    _thumb.backgroundColor = [LQSTheme primary];
    _inactive.backgroundColor = [LQSTheme surfaceEffect1]; // SystemUISliderColors.kt:31
    _auto.backgroundColor = _autoOn ? [LQSTheme primary] : [LQSTheme surfaceEffect1];
    _auto.tintColor = _autoOn ? [LQSTheme onPrimary] : [LQSTheme onSurface];
    [_auto setImage:[LQSVectorIcon imageNamed:(_autoOn ? @"ic_qs_brightness_auto_on" : @"ic_qs_brightness_auto_off") side:24] forState:UIControlStateNormal];
}

- (void)setAutoOn:(BOOL)on { _autoOn = on; [self applyColors]; }
- (void)setShowAuto:(BOOL)s { _showAuto = s; _auto.hidden = !s; [self setNeedsLayout]; }
- (void)autoTapped {
    LQSHapticTick();
    self.autoOn = !_autoOn;
    if (self.onAutoToggle) self.onAutoToggle(_autoOn);
}

- (void)setValue:(CGFloat)value {
    _value = MAX(0, MIN(1, value));
    self.accessibilityValue = [NSString stringWithFormat:@"%d%%", (int)round(_value * 100)];
    [self setNeedsLayout];
}

- (CGFloat)trackWidth { return self.bounds.size.width - (_showAuto ? 52 + 10 : 0); }

static UIBezierPath *TrackPath(CGRect r, CGFloat outer, CGFloat inner, BOOL leftOuter) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat l = leftOuter ? outer : inner, rr = leftOuter ? inner : outer;
    l = MIN(l, r.size.width / 2); rr = MIN(rr, r.size.width / 2);
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    [p moveToPoint:CGPointMake(x0 + l, y0)];
    [p addLineToPoint:CGPointMake(x1 - rr, y0)];
    [p addArcWithCenter:CGPointMake(x1 - rr, y0 + rr) radius:rr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(x1, y1 - rr)];
    [p addArcWithCenter:CGPointMake(x1 - rr, y1 - rr) radius:rr startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(x0 + l, y1)];
    [p addArcWithCenter:CGPointMake(x0 + l, y1 - l) radius:l startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(x0, y0 + l)];
    [p addArcWithCenter:CGPointMake(x0 + l, y0 + l) radius:l startAngle:M_PI endAngle:1.5 * M_PI clockwise:YES];
    [p closePath];
    return p;
}

static void ShapeMask(UIView *v, UIBezierPath *path) {
    CAShapeLayer *m = (CAShapeLayer *)v.layer.mask;
    if (![m isKindOfClass:CAShapeLayer.class]) { m = [CAShapeLayer layer]; v.layer.mask = m; }
    m.frame = v.bounds;
    m.path = path.CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, tw = [self trackWidth], track = 40, gap = 6, thumbW = 4, thumbH = 52;
    CGFloat ty = (h - track) / 2;
    CGFloat minX = gap, maxX = tw - thumbW - gap;
    CGFloat tx = minX + (maxX - minX) * _value; // thumb left edge
    CGRect a = CGRectMake(0, ty, MAX(0, tx - gap), track), in = CGRectMake(tx + thumbW + gap, ty, MAX(0, tw - (tx + thumbW + gap)), track);
    _active.frame = a;
    _inactive.frame = in;
    ShapeMask(_active, TrackPath(_active.bounds, 12, 2, YES));
    ShapeMask(_inactive, TrackPath(_inactive.bounds, 12, 2, NO));
    _active.hidden = a.size.width < 1;
    _thumb.frame = CGRectMake(tx, (h - thumbH) / 2, thumbW, thumbH);
    _thumb.layer.cornerRadius = thumbW / 2;
    // getIconForPercentage: <=20 low, >=80 high, else mid (BrightnessSliderViewModel.kt:159-165).
    CGFloat pct = _value * 100;
    NSString *name = pct <= 20 ? @"ic_brightness_low" : pct >= 80 ? @"ic_brightness_full" : @"ic_brightness_medium";
    CGFloat icon = 28, inset = 6;
    BOOL inActive = a.size.width >= icon + 2 * inset;
    _iconView.image = [LQSVectorIcon imageNamed:name side:20];
    _iconView.tintColor = inActive ? [LQSTheme onPrimary] : [LQSTheme onSurface];
    _iconView.frame = inActive ? CGRectMake(inset, ty + (track - icon) / 2, icon, icon) : CGRectMake(CGRectGetMinX(in) + inset, ty + (track - icon) / 2, icon, icon);
    _auto.frame = CGRectMake(tw + 10, (h - 52) / 2, 52, 52);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self applyColors]; }

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g != _drag && g != _tapper) return YES; // the panel's vertical drag may start here too
    CGPoint p = [g locationInView:self];
    if (p.x > [self trackWidth]) return NO; // auto button
    if ([g isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
        return fabs(v.x) > fabs(v.y);
    }
    return YES;
}

- (CGFloat)valueAt:(CGFloat)x {
    CGFloat tw = [self trackWidth];
    return (x - 6 - 2) / MAX(1, tw - 4 - 12);
}

// SliderHapticFeedbackProvider: drag texture ticks while the value moves, a
// stronger click at the limits. Always on (independent of the tile haptics setting).
static void SliderTicks(CGFloat old, CGFloat now) {
    static UISelectionFeedbackGenerator *tick;
    static UIImpactFeedbackGenerator *edge;
    static CFTimeInterval last;
    if (!tick) { tick = [UISelectionFeedbackGenerator new]; edge = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]; }
    if ((old > 0 && now <= 0) || (old < 1 && now >= 1)) { [edge impactOccurred]; return; }
    CFTimeInterval t = CACurrentMediaTime();
    if (floor(old * 25) != floor(now * 25) && t - last > 0.03) { [tick selectionChanged]; last = t; } // every 4% (assumption)
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) { _startValue = _value; _dragging = YES; if (self.onDragChanged) self.onDragChanged(YES); }
    CGFloat old = _value;
    self.value = _startValue + [g translationInView:self].x / MAX(1, [self trackWidth] - 16);
    SliderTicks(old, _value);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) { _dragging = NO; if (self.onDragChanged) self.onDragChanged(NO); }
}

- (void)tap:(UITapGestureRecognizer *)g {
    CGFloat old = _value;
    self.value = [self valueAt:[g locationInView:self].x];
    SliderTicks(old, _value);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)accessibilityIncrement { self.value += 0.1; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)accessibilityDecrement { self.value -= 0.1; [self sendActionsForControlEvents:UIControlEventValueChanged]; }

@end

#pragma mark - Battery

static NSDictionary *BatteryGlyphs(void) {
    static NSDictionary *g;
    if (!g && [LQSTheme resourceRoot]) {
        NSData *d = [NSData dataWithContentsOfFile:[[LQSTheme resourceRoot] stringByAppendingPathComponent:@"battery_glyphs.json"]];
        g = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    }
    return g;
}

static NSString *const kCap = @"M0.3333,-0.0037L0,-0.0037L0,6.0234L0.3333,6.0234C0.9777,6.0234 1.5,5.5011 1.5,4.8567L1.5,1.163C1.5,0.5187 0.9777,-0.0037 0.3333,-0.0037Z";

@implementation LQSBatteryView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { self.opaque = NO; self.backgroundColor = UIColor.clearColor; self.isAccessibilityElement = YES; _darkBackground = YES; _level = 50; }
    return self;
}
- (void)setLevel:(NSInteger)level { _level = MAX(0, MIN(100, level)); self.accessibilityLabel = [NSString stringWithFormat:@"%ld%%", (long)_level]; [self setNeedsDisplay]; }
- (void)setCharging:(BOOL)c { _charging = c; [self setNeedsDisplay]; }
- (void)setPowerSave:(BOOL)p { _powerSave = p; [self setNeedsDisplay]; }
- (void)setShowPercent:(BOOL)s { _showPercent = s; [self setNeedsDisplay]; }
- (void)setDarkBackground:(BOOL)d { _darkBackground = d; [self setNeedsDisplay]; }

- (NSString *)attribution { return self.charging ? @"Bolt" : self.powerSave ? @"Plus" : nil; }

// Body 24x13 (BatteryFrame.bodyPathSpec); cap 1.5x6.03 after 1dp, or the
// attribution glyph overlapping the body by 20% of its width (BatteryMeasurePolicy).
- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat s = (size.height > 0 && size.height < 1000 ? size.height : 13) / 13.0;
    NSDictionary *attr = [self attribution] ? BatteryGlyphs()[[self attribution]] : nil;
    CGFloat w = 24 * s + (attr ? [attr[@"w"] doubleValue] * s * 0.8 : 1.5 * s + s);
    return CGSizeMake(ceil(w), 13 * s);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat s = self.bounds.size.height / 13.0;
    CGContextScaleCTM(ctx, s, s);
    BOOL dark = self.darkBackground;
    // BatteryColors.kt
    UIColor *fill = self.charging ? [UIColor colorWithRed:0x18 / 255.0 green:0xcc / 255.0 blue:0x47 / 255.0 alpha:1]
                  : self.powerSave ? [UIColor colorWithRed:1 green:0xc9 / 255.0 blue:0x17 / 255.0 alpha:1]
                  : (self.level <= 5 ? [UIColor colorWithRed:1 green:0x0e / 255.0 blue:0x01 / 255.0 alpha:1] // isCritical threshold: assumption
                     : (dark ? UIColor.whiteColor : UIColor.blackColor));
    NSMutableArray *digits = [NSMutableArray array];
    if (self.showPercent) {
        NSArray *names = @[@"Zero", @"One", @"Two", @"Three", @"Four", @"Five", @"Six", @"Seven", @"Eight", @"Nine"];
        for (NSUInteger i = 0; i < [@(self.level) stringValue].length; i++) [digits addObject:names[[[@(self.level) stringValue] characterAtIndex:i] - '0']];
    }
    BOOL full = self.level >= 100 && !digits.count;
    UIColor *bgOnly = dark ? [UIColor colorWithWhite:1 alpha:0.45] : [UIColor colorWithWhite:0 alpha:0.20];
    UIColor *bgGlyph = dark ? [UIColor colorWithWhite:1 alpha:0.55] : (self.charging || self.powerSave ? [UIColor colorWithWhite:0 alpha:0.20] : [UIColor colorWithWhite:0 alpha:0.55]);
    UIColor *frameColor = full ? fill : (digits.count ? bgGlyph : bgOnly);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 24, 13) cornerRadius:4];
    [frameColor setFill];
    [body fill];
    if (!full && self.level > 0) {
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectMake(0, 0, ceil(self.level / 100.0 * 24), 13));
        [fill setFill];
        [body fill];
        CGContextRestoreGState(ctx);
    }
    NSDictionary *glyphs = BatteryGlyphs();
    if (digits.count) {
        CGFloat total = 0;
        for (NSString *n in digits) total += [glyphs[n][@"w"] doubleValue];
        total += 0.8 * (digits.count - 1); // INTER_GLYPH_PADDING_PX
        CGFloat x = (24 - total) / 2;
        // Glyph colour: DarkTheme black @ 0.75; LightTheme.Default white @ 0.9, others black @ 0.75.
        UIColor *glyphColor = (!dark && !self.charging && !self.powerSave) ? [UIColor colorWithWhite:1 alpha:0.9] : [UIColor colorWithWhite:0 alpha:0.75];
        for (NSString *n in digits) {
            NSDictionary *g = glyphs[n];
            CGPathRef p = [LQSVectorIcon newPathFromString:g[@"d"]];
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, x, (13 - [g[@"h"] doubleValue]) / 2);
            CGContextAddPath(ctx, p);
            CGContextSetFillColorWithColor(ctx, glyphColor.CGColor);
            CGContextFillPath(ctx);
            CGContextRestoreGState(ctx);
            if (p) CGPathRelease(p);
            x += [g[@"w"] doubleValue] + 0.8;
        }
    }
    NSString *attrName = [self attribution];
    UIColor *attrColor = dark ? UIColor.whiteColor : UIColor.blackColor;
    if (attrName && glyphs[attrName]) {
        NSDictionary *g = glyphs[attrName];
        CGFloat gw = [g[@"w"] doubleValue], gh = [g[@"h"] doubleValue];
        CGPathRef p = [LQSVectorIcon newPathFromString:g[@"d"]];
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 24 - 0.2 * gw, (13 - gh) / 2);
        // Clear a 2px stroke around the glyph (BlendMode.Clear), then draw it.
        CGContextSetBlendMode(ctx, kCGBlendModeClear);
        CGContextSetLineWidth(ctx, 2);
        CGContextAddPath(ctx, p);
        CGContextStrokePath(ctx);
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);
        CGContextAddPath(ctx, p);
        CGContextSetFillColorWithColor(ctx, attrColor.CGColor);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
        if (p) CGPathRelease(p);
    } else {
        CGPathRef p = [LQSVectorIcon newPathFromString:kCap];
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 25, (13 - 6.03) / 2);
        CGContextAddPath(ctx, p);
        CGContextSetFillColorWithColor(ctx, frameColor.CGColor);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
        if (p) CGPathRelease(p);
    }
}

@end

#pragma mark - Header

static NSString *DataTypeIcon(NSString *t) {
    if (![t isKindOfClass:NSString.class] || !t.length) return nil;
    NSDictionary *m = @{@"G": @"ic_g_mobiledata", @"E": @"ic_e_mobiledata", @"1X": @"ic_1x_mobiledata", @"3G": @"ic_3g_mobiledata",
                        @"H": @"ic_h_mobiledata", @"H+": @"ic_h_plus_mobiledata", @"4G": @"ic_4g_mobiledata", @"4G+": @"ic_4g_plus_mobiledata",
                        @"LTE": @"ic_lte_mobiledata", @"LTE+": @"ic_lte_plus_mobiledata", @"LTE-A": @"ic_lte_plus_mobiledata",
                        @"5G": @"ic_5g_mobiledata", @"5G+": @"ic_5g_plus_mobiledata", @"5GE": @"ic_5g_e_mobiledata"};
    return m[t.uppercaseString] ?: m[t];
}

// ShadeHeader.kt: collapsed row (clock 14sp + date, 5dp spacing | status icons +
// battery chip) and ExpandedShadeHeader (Column min 120dp, bottom aligned, 16dp
// spacing: clock scaled 2.57 | carrier max 180dp; date | chip). Cross-fade as in
// FromShadeToQuickSettingsTransition: collapsed out over [0, 0.14], expanded in from 0.58.
@implementation LQSHeaderView {
    UIView *_collapsed, *_expanded;
    UILabel *_clock, *_date, *_bigClock, *_bigDate, *_carrier;
    UIView *_chip, *_bigChip;
    UIImageView *_wifi, *_signal, *_type, *_bigWifi, *_bigSignal, *_bigType;
    LQSBatteryView *_battery, *_bigBattery;
    UILabel *_bigPercent;
    NSDictionary *_info;
    NSTimer *_timer;
}

- (UILabel *)label:(CGFloat)size weight:(CGFloat)w in:(UIView *)v {
    UILabel *l = [UILabel new];
    l.font = [LQSTheme sansWithSize:size weight:w];
    l.textColor = [LQSTheme headerText];
    [v addSubview:l];
    return l;
}

- (UIView *)chipIn:(UIView *)v wifi:(UIImageView *__strong *)wifi signal:(UIImageView *__strong *)sig type:(UIImageView *__strong *)type battery:(LQSBatteryView *__strong *)bat {
    UIView *c = [UIView new];
    [v addSubview:c];
    *type = [UIImageView new];
    *sig = [UIImageView new];
    *wifi = [UIImageView new];
    for (UIImageView *iv in @[*type, *sig, *wifi]) { iv.contentMode = UIViewContentModeScaleAspectFit; iv.tintColor = [LQSTheme headerText]; [c addSubview:iv]; }
    *bat = [LQSBatteryView new];
    [c addSubview:*bat];
    return c;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _collapsed = [UIView new];
        _expanded = [UIView new];
        [self addSubview:_collapsed];
        [self addSubview:_expanded];
        _clock = [self label:14 weight:500 in:_collapsed]; // status_bar_clock_size 14sp, variable-body-medium-emphasized
        _date = [self label:14 weight:500 in:_collapsed];
        _chip = [self chipIn:_collapsed wifi:&_wifi signal:&_signal type:&_type battery:&_battery];
        // Clock scaled 2.57x (ShadeHeader.kt:317); drawn at the scaled size to stay sharp.
        _bigClock = [self label:14 * 2.57 weight:500 in:_expanded];
        _carrier = [self label:14 weight:500 in:_expanded];
        _carrier.textAlignment = NSTextAlignmentRight;
        _bigDate = [self label:14 weight:500 in:_expanded];
        _bigChip = [self chipIn:_expanded wifi:&_bigWifi signal:&_bigSignal type:&_bigType battery:&_bigBattery];
        _bigPercent = [self label:14 weight:500 in:_bigChip];
        for (UILabel *l in @[_clock, _bigClock]) {
            l.userInteractionEnabled = YES;
            [l addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clockTapped)]];
        }
        for (UILabel *l in @[_date, _bigDate]) {
            l.userInteractionEnabled = YES;
            [l addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dateTapped)]];
        }
        [self refresh];
    }
    return self;
}

- (void)clockTapped { if (self.onClockTap) self.onClockTap(); }
- (void)dateTapped { if (self.onDateTap) self.onDateTap(); }

- (CGFloat)collapsedHeight { return 48; } // qqsHeaderHeight: 48dp touch row (assumption for the iPhone 8 20pt status bar)
- (CGFloat)expandedHeight { return 120; } // ExpandedHeight

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (self.window) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
        [self refresh];
    }
}

- (void)refresh {
    NSDate *now = [NSDate date];
    static NSDateFormatter *tf, *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tf = [NSDateFormatter new];
        // Lineage STATUS_BAR_AM_PM default AM_PM_STYLE_GONE: no AM/PM marker.
        NSString *fmt = [NSDateFormatter dateFormatFromTemplate:@"jm" options:0 locale:NSLocale.currentLocale];
        tf.dateFormat = [[fmt stringByReplacingOccurrencesOfString:@"a" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        df = [NSDateFormatter new];
        // abbrev_wday_month_day_no_year ("EEE, MMM d"); localised via template (strings not in the clone).
        df.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEMMMd" options:0 locale:NSLocale.currentLocale];
    });
    _clock.text = _bigClock.text = [tf stringFromDate:now];
    _date.text = _bigDate.text = [df stringFromDate:now];
    UIDevice *dev = UIDevice.currentDevice;
    dev.batteryMonitoringEnabled = YES;
    NSInteger lvl = dev.batteryLevel >= 0 ? (NSInteger)round(dev.batteryLevel * 100) : 50;
    BOOL charging = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    for (LQSBatteryView *b in @[_battery, _bigBattery]) {
        b.level = lvl;
        b.charging = charging;
        b.powerSave = NSProcessInfo.processInfo.isLowPowerModeEnabled;
        b.darkBackground = self.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight;
    }
    _battery.showPercent = YES; // assumption: percent inside the icon (iOS shows it on iPhone 8 by setting)
    _bigPercent.text = [NSString stringWithFormat:@"%ld%%", (long)lvl]; // useExpandedFormat: text next to the icon
    [self setNeedsLayout];
}

- (void)applyLiveInfo:(NSDictionary *)info {
    _info = info;
    BOOL wifiOn = [info[@"wifiAssociated"] boolValue];
    // newStatusBarIcons (Pixel builds of Android 17): 3-bar ic_wifi_0..3 (WifiIcons.java:35-45).
    NSInteger bars = MAX(0, MIN(3, [info[@"wifiBars"] integerValue]));
    NSString *wifiIcon = wifiOn ? [NSString stringWithFormat:@"ic_wifi_%ld", (long)bars] : nil;
    BOOL sim = info && ![info[@"noSIM"] boolValue];
    NSInteger cbars = MAX(0, MIN(4, [info[@"cellBars"] integerValue]));
    NSString *cellIcon = sim ? [NSString stringWithFormat:@"ic_mobile_%ld_4_bar", (long)cbars] : nil;
    NSString *typeIcon = sim && !wifiOn ? DataTypeIcon(info[@"network"]) : nil; // AOSP hides the data type on Wi-Fi
    for (NSArray *set in @[@[_wifi, _signal, _type], @[_bigWifi, _bigSignal, _bigType]]) {
        UIImageView *w = set[0], *s = set[1], *t = set[2];
        // Drawn at their own dp size (ic_wifi_N 17x12.58, ic_mobile_N_4_bar 17x12, data type 26x16).
        w.image = wifiIcon ? [LQSVectorIcon imageNamed:wifiIcon height:12.58] : nil;
        s.image = cellIcon ? [LQSVectorIcon imageNamed:cellIcon height:12] : nil;
        t.image = typeIcon ? [LQSVectorIcon imageNamed:typeIcon height:16] : nil;
    }
    NSString *carrier = [info[@"carrier"] isKindOfClass:NSString.class] ? info[@"carrier"] : @"";
    if (!sim) carrier = LQSL(@"keyguard_missing_sim_message_short");
    _carrier.text = carrier;
    [self setNeedsLayout];
}

static CGFloat LayoutChip(UIView *chip, NSArray<UIImageView *> *icons, LQSBatteryView *battery, UILabel *percent, CGFloat height) {
    CGFloat x = 6; // chip padding horizontal 6dp
    for (UIImageView *iv in icons) {
        if (!iv.image) { iv.frame = CGRectZero; continue; }
        CGSize s = iv.image.size; // natural size, vertically centred
        iv.frame = CGRectMake(x, round((height - s.height) / 2 * 2) / 2, s.width, s.height);
        x = CGRectGetMaxX(iv.frame) + 4; // status icon spacing (assumption: 4dp)
    }
    x -= 1; // StatusIcons paddingEnd 3sp after the last icon
    CGSize bs = [battery sizeThatFits:CGSizeMake(0, 13)];
    battery.frame = CGRectMake(x, (height - 13) / 2, bs.width, 13);
    [battery setNeedsDisplay];
    x = CGRectGetMaxX(battery.frame);
    if (percent) {
        CGSize ps = [percent sizeThatFits:CGSizeMake(100, height)];
        percent.frame = CGRectMake(x + 4, (height - ps.height) / 2, ps.width, ps.height); // BatteryWithEstimate spacing 4dp
        x = CGRectGetMaxX(percent.frame);
    }
    return x + 6;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, pad = [LQSTheme sideInset];
    _collapsed.frame = CGRectMake(0, 0, w, [self collapsedHeight]);
    _expanded.frame = CGRectMake(0, 0, w, [self expandedHeight]);
    // Collapsed: one row centred in the 48dp header.
    CGFloat ch = [self collapsedHeight];
    CGSize cs = [_clock sizeThatFits:CGSizeMake(200, ch)];
    _clock.frame = CGRectMake(pad, (ch - 20) / 2, cs.width, 20);
    CGSize ds = [_date sizeThatFits:CGSizeMake(200, ch)];
    _date.frame = CGRectMake(CGRectGetMaxX(_clock.frame) + 5, (ch - 20) / 2, ds.width, 20);
    CGFloat chipW = LayoutChip(_chip, @[_type, _signal, _wifi], _battery, nil, 24);
    _chip.frame = CGRectMake(w - pad - chipW + 6, (ch - 24) / 2, chipW, 24);
    // Expanded: bottom-aligned column inside 120dp, 16dp spacing.
    CGFloat eh = [self expandedHeight], rowDate = 20, bigH = 20 * 2.57;
    CGFloat top = eh - rowDate - 16 - bigH;
    CGSize bs = [_bigClock sizeThatFits:CGSizeMake(300, bigH)];
    _bigClock.frame = CGRectMake(pad, top, bs.width, bigH);
    _carrier.frame = CGRectMake(w - pad - 180, top + (bigH - 20) / 2, 180, 20);
    CGSize bds = [_bigDate sizeThatFits:CGSizeMake(220, 20)];
    _bigDate.frame = CGRectMake(pad, eh - rowDate, bds.width, rowDate);
    CGFloat bigChipW = LayoutChip(_bigChip, @[_bigType, _bigSignal, _bigWifi], _bigBattery, _bigPercent, 24);
    _bigChip.frame = CGRectMake(w - pad - bigChipW + 6, eh - rowDate - 2, bigChipW, 24);
    [self applyExpansion];
}

- (void)setExpansion:(CGFloat)e {
    _expansion = MAX(0, MIN(1, e));
    [self applyExpansion];
}

- (void)applyExpansion {
    CGFloat e = _expansion;
    _collapsed.alpha = 1 - MIN(1, e / 0.14);
    _expanded.alpha = MAX(0, (e - 0.58) / 0.42);
    _collapsed.userInteractionEnabled = e < 0.5;
    _expanded.userInteractionEnabled = e >= 0.5;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self refresh]; }

@end

#pragma mark - Buttons

@implementation LQSIconButton {
    UIImageView *_iv;
}
- (instancetype)initWithIcon:(NSString *)icon side:(CGFloat)side {
    if ((self = [super initWithFrame:CGRectZero])) {
        _iv = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:icon side:side]];
        _iv.contentMode = UIViewContentModeCenter;
        _iv.userInteractionEnabled = NO;
        [self addSubview:_iv];
        self.fill = [LQSTheme surfaceEffect1];
        self.glyph = [LQSTheme onSurface];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self addTarget:self action:@selector(down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    }
    return self;
}
- (void)setFill:(UIColor *)fill { _fill = fill; self.backgroundColor = fill; }
- (void)setGlyph:(UIColor *)glyph { _glyph = glyph; _iv.tintColor = glyph; }
- (void)layoutSubviews { [super layoutSubviews]; _iv.frame = self.bounds; self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) / 2; }
- (void)down { [UIView animateWithDuration:0.1 animations:^{ self.alpha = 0.7; }]; }
- (void)up { [UIView animateWithDuration:0.15 animations:^{ self.alpha = 1; }]; }
@end

@implementation LQSPageDots {
    NSMutableArray<UIView *> *_dots;
}
- (void)setPages:(NSInteger)pages { _pages = pages; [self setNeedsLayout]; }
- (void)setPosition:(CGFloat)p { _position = p; [self setNeedsLayout]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_dots) _dots = [NSMutableArray array];
    while ((NSInteger)_dots.count < _pages) { UIView *d = [UIView new]; [self addSubview:d]; [_dots addObject:d]; }
    while ((NSInteger)_dots.count > _pages) { [_dots.lastObject removeFromSuperview]; [_dots removeLastObject]; }
    // Dot 6dp, step 12dp, active onSurface, inactive onSurface @ 0.38 (assumption: PagerDots defaults).
    CGFloat d = 6, step = 12, total = (_pages - 1) * step + d;
    CGFloat x0 = (self.bounds.size.width - total) / 2, y = (self.bounds.size.height - d) / 2;
    for (NSInteger i = 0; i < _pages; i++) {
        UIView *v = _dots[i];
        CGFloat t = MAX(0, 1 - fabs(_position - i));
        v.frame = CGRectMake(x0 + i * step, y, d, d);
        v.layer.cornerRadius = d / 2;
        v.backgroundColor = [[LQSTheme onSurface] colorWithAlphaComponent:0.38 + 0.62 * t];
        v.hidden = _pages < 2;
    }
}
@end
