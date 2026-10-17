#import "LQSColorsViewController.h"
#import "LQSMonet.h"
#import "LQSTheme.h"
#import "LQSStrings.h"
#import "LQSVectorIcon.h"
#import "LQSWallpaper.h"
#import <CoreImage/CoreImage.h>
#import <objc/message.h>
#import <notify.h>

NSString *const LQSThemeChangedNotification = @"com.makr.materialyou/theme-changed";

static UIColor *ARGB(NSNumber *n) {
    unsigned v = n.unsignedIntValue;
    return [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0 green:((v >> 8) & 0xff) / 255.0 blue:(v & 0xff) / 255.0 alpha:((v >> 24) & 0xff) / 255.0];
}

static NSArray<NSString *> *Styles(void) { return @[@"neutral", @"tonal_spot", @"vibrant", @"expressive"]; }

// ThemePicker strings (values/strings.xml + values-ru; not part of Resources/strings).
static NSString *T(NSString *key) {
    BOOL ru = [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"];
    NSDictionary *en = @{@"title": @"Colors", @"apply": @"Apply", @"wallpaper": @"Your wallpaper colors", @"other": @"Other colors",
                         @"dark": @"Dark theme", @"select": @"Select a color", @"neutral": @"Neutral", @"tonal_spot": @"Soft",
                         @"vibrant": @"Bright", @"expressive": @"Bold", @"custom": @"Custom color"};
    NSDictionary *rus = @{@"title": @"Цвета", @"apply": @"Применить", @"wallpaper": @"Цвета обоев", @"other": @"Другие цвета",
                          @"dark": @"Тёмная тема", @"select": @"Выберите цвет", @"neutral": @"Нейтральная", @"tonal_spot": @"Мягкая",
                          @"vibrant": @"Яркая", @"expressive": @"Насыщенная", @"custom": @"Пользовательский цвет"};
    return (ru ? rus : en)[key] ?: key;
}

typedef NS_ENUM(NSInteger, LQSColorsMode) { LQSColorsModeLanding, LQSColorsModeFreeform, LQSColorsModeVariant };

#pragma mark - Rainbow slider (BrushSlider: track 28dp, corners 10.5 / 2dp, 6dp thumb gap)

@interface LQSHueSlider : UIControl
@property (nonatomic) double hue; // 0...360
@property (nonatomic, strong) UIColor *thumbColor;
@end

@implementation LQSHueSlider {
    CAGradientLayer *_left, *_right;
    CAShapeLayer *_leftMask, *_rightMask;
    UIView *_thumb;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // FreeformColorPicker.kt:60-73: 13 stops every 30 degrees starting at 330, HSV(s 0.6, v 0.8).
        NSMutableArray *cols = [NSMutableArray array];
        for (int i = 0; i <= 12; i++) {
            double h = fmod(330 + i * 30, 360) / 360.0;
            [cols addObject:(id)[UIColor colorWithHue:h saturation:0.6 brightness:0.8 alpha:1].CGColor];
        }
        _left = [CAGradientLayer layer];
        _right = [CAGradientLayer layer];
        for (CAGradientLayer *g in @[_left, _right]) {
            g.colors = cols;
            g.startPoint = CGPointMake(0, 0.5);
            g.endPoint = CGPointMake(1, 0.5);
            [self.layer addSublayer:g];
        }
        _leftMask = [CAShapeLayer layer];
        _rightMask = [CAShapeLayer layer];
        _left.mask = _leftMask;
        _right.mask = _rightMask;
        _thumb = [UIView new];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
        _hue = 180; // ColorPickerViewModel.kt:444
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    }
    return self;
}
- (void)setHue:(double)hue { _hue = MAX(0, MIN(360, hue)); [self setNeedsLayout]; }
- (void)setThumbColor:(UIColor *)c { _thumbColor = c; _thumb.backgroundColor = c; }
static UIBezierPath *Track(CGRect r, CGFloat outer, CGFloat inner, BOOL left) {
    CGFloat tl = left ? outer : inner, tr = left ? inner : outer;
    tl = MIN(tl, r.size.width / 2); tr = MIN(tr, r.size.width / 2);
    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    [p moveToPoint:CGPointMake(x0 + tl, y0)];
    [p addLineToPoint:CGPointMake(x1 - tr, y0)];
    [p addArcWithCenter:CGPointMake(x1 - tr, y0 + tr) radius:tr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(x1, y1 - tr)];
    [p addArcWithCenter:CGPointMake(x1 - tr, y1 - tr) radius:tr startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(x0 + tl, y1)];
    [p addArcWithCenter:CGPointMake(x0 + tl, y1 - tl) radius:tl startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(x0, y0 + tl)];
    [p addArcWithCenter:CGPointMake(x0 + tl, y0 + tl) radius:tl startAngle:M_PI endAngle:1.5 * M_PI clockwise:YES];
    [p closePath];
    return p;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height, track = 28, gap = 6, tw = 4;
    CGFloat x = gap + (w - 2 * gap - tw) * (_hue / 360.0);
    CGRect full = CGRectMake(0, (h - track) / 2, w, track);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _left.frame = self.bounds;
    _right.frame = self.bounds;
    _leftMask.path = Track(CGRectMake(0, full.origin.y, MAX(0, x - gap), track), 10.5, 2, YES).CGPath;
    _rightMask.path = Track(CGRectMake(x + tw + gap, full.origin.y, MAX(0, w - x - tw - gap), track), 10.5, 2, NO).CGPath;
    [CATransaction commit];
    _thumb.frame = CGRectMake(x, (h - 44) / 2, tw, 44); // M3 slider thumb 4x44dp (default, assumption)
    _thumb.layer.cornerRadius = 2;
}
- (void)drag:(UIGestureRecognizer *)g {
    CGFloat w = self.bounds.size.width;
    double old = _hue;
    self.hue = ([g locationInView:self].x - 6) / MAX(1, w - 16) * 360.0;
    if ((int)(old / 10) != (int)(_hue / 10)) {
        static UISelectionFeedbackGenerator *t;
        if (!t) t = [UISelectionFeedbackGenerator new];
        [t selectionChanged];
    }
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

#pragma mark - Preview (lock screen + shade, like the ThemePicker preview card)

@interface LQSThemePreview : UIView
@property (nonatomic, strong, nullable) UIImage *wallpaper;
- (void)applyScheme:(NSDictionary<NSString *, NSNumber *> *)s dark:(BOOL)dark;
@end

@implementation LQSThemePreview {
    UIImageView *_bg;
    UIView *_shade;
    UILabel *_date, *_clock;
    UIView *_brightActive, *_brightInactive, *_brightThumb;
    NSMutableArray<UIView *> *_tiles;
    NSMutableArray<UIView *> *_bars;
    NSMutableArray<UIImageView *> *_icons;
    UILabel *_wifiTitle, *_wifiSub;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 32;
        _bg = [UIImageView new];
        _bg.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_bg];
        _shade = [UIView new];
        [self addSubview:_shade];
        _date = [UILabel new];
        _clock = [UILabel new];
        [self addSubview:_date];
        [self addSubview:_clock];
        _brightActive = [UIView new]; _brightInactive = [UIView new]; _brightThumb = [UIView new];
        for (UIView *v in @[_brightInactive, _brightActive, _brightThumb]) [self addSubview:v];
        _tiles = [NSMutableArray array];
        _bars = [NSMutableArray array];
        _icons = [NSMutableArray array];
        NSArray *icons = @[@"ic_wifi_3", @"qs_bluetooth_icon_on", @"qs_dnd_icon_on", @"ic_cast", @"qs_location_icon_on", @"ic_brightness_full", @"qs_mic_access_on", @"ic_alarm"];
        for (NSUInteger i = 0; i < 8; i++) {
            UIView *t = [UIView new];
            [self addSubview:t];
            [_tiles addObject:t];
            UIImageView *iv = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:icons[i] side:20]];
            iv.contentMode = UIViewContentModeCenter;
            [t addSubview:iv];
            [_icons addObject:iv];
        }
        for (NSUInteger i = 0; i < 6; i++) { UIView *b = [UIView new]; b.layer.cornerRadius = 3; [self addSubview:b]; [_bars addObject:b]; }
        _wifiTitle = [UILabel new]; _wifiSub = [UILabel new];
        [_tiles[0] addSubview:_wifiTitle];
        [_tiles[0] addSubview:_wifiSub];
        _wifiTitle.text = LQSL(@"quick_settings_wifi_label");
        _wifiSub.text = @"Home";
    }
    return self;
}
- (void)setWallpaper:(UIImage *)img {
    _wallpaper = img;
    if (!img) { _bg.image = nil; return; }
    CIImage *ci = [CIImage imageWithCGImage:img.CGImage];
    CIFilter *f = [CIFilter filterWithName:@"CIGaussianBlur"];
    [f setValue:[ci imageByClampingToExtent] forKey:kCIInputImageKey];
    [f setValue:@(40) forKey:kCIInputRadiusKey];
    CIImage *out = [f.outputImage imageByCroppingToRect:ci.extent];
    CGImageRef cg = [[CIContext contextWithOptions:nil] createCGImage:out fromRect:ci.extent];
    _bg.image = cg ? [UIImage imageWithCGImage:cg] : img;
    if (cg) CGImageRelease(cg);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, s = w / 360.0; // preview scale (dp)
    _bg.frame = self.bounds;
    _shade.frame = self.bounds;
    CGFloat pad = 16 * s, y = 56 * s;
    _date.font = [LQSTheme sansWithSize:MAX(8, 14 * s * 1.2) weight:500];
    _clock.font = [LQSTheme sansWithSize:52 * s * 1.3 weight:400];
    _date.frame = CGRectMake(pad, y, w - 2 * pad, 20 * s * 1.2);
    y = CGRectGetMaxY(_date.frame);
    CGSize cs = [_clock sizeThatFits:CGSizeMake(w, 200)];
    _clock.frame = CGRectMake(pad - 2 * s, y, w - 2 * pad, cs.height);
    y = CGRectGetMaxY(_clock.frame) + 12 * s;
    CGFloat trackH = 40 * s, tw = w - 2 * pad, ax = tw * 0.78;
    _brightActive.frame = CGRectMake(pad, y, ax - 6 * s, trackH);
    _brightThumb.frame = CGRectMake(pad + ax, y - 6 * s, 4 * s, trackH + 12 * s);
    _brightInactive.frame = CGRectMake(pad + ax + 10 * s, y, tw - ax - 10 * s, trackH);
    _brightActive.layer.cornerRadius = _brightInactive.layer.cornerRadius = 12 * s;
    _brightThumb.layer.cornerRadius = 2 * s;
    y = CGRectGetMaxY(_brightActive.frame) + 16 * s;
    CGFloat gap = 8 * s, th = 72 * s, cw = (tw - 3 * gap) / 4;
    for (NSUInteger i = 0; i < 8; i++) {
        UIView *t = _tiles[i];
        BOOL large = i < 4;
        NSInteger row = large ? i / 2 : 2, col = large ? (i % 2) * 2 : i - 4;
        CGFloat x = pad + col * (cw + gap), tileW = large ? 2 * cw + gap : cw;
        t.frame = CGRectMake(x, y + row * (th + gap), tileW, th);
        t.layer.cornerRadius = (i == 0) ? 24 * s : th / 2;
        UIImageView *iv = _icons[i];
        iv.frame = large ? CGRectMake(8 * s, (th - 56 * s) / 2, 56 * s, 56 * s) : t.bounds;
    }
    _wifiTitle.font = [LQSTheme sansWithSize:MAX(7, 14 * s) weight:600];
    _wifiSub.font = [LQSTheme sansWithSize:MAX(6, 12 * s) weight:500];
    _wifiTitle.frame = CGRectMake(70 * s, th / 2 - 18 * s, 2 * cw, 18 * s);
    _wifiSub.frame = CGRectMake(70 * s, th / 2, 2 * cw, 16 * s);
    // Placeholder bars on the other large tiles (like the ThemePicker preview).
    for (NSUInteger i = 0; i < 6; i++) {
        UIView *t = _tiles[1 + i / 2];
        BOOL top = (i % 2) == 0;
        _bars[i].frame = CGRectMake(CGRectGetMinX(t.frame) + 70 * s, CGRectGetMidY(t.frame) + (top ? -12 * s : 4 * s), top ? 70 * s : 40 * s, 8 * s);
    }
}
- (void)applyScheme:(NSDictionary<NSString *, NSNumber *> *)c dark:(BOOL)dark {
    UIColor *(^C)(NSString *) = ^UIColor *(NSString *k) { return c[k] ? ARGB(c[k]) : UIColor.grayColor; };
    // Shade panel over the wallpaper: accent1 800/100 @0.32 over neutral @0.32 over #404040 @0.40 (≈0.72 alpha).
    UIColor *fg = C(dark ? @"accent1_800" : @"accent1_100");
    CGFloat r, g, b, a;
    [fg getRed:&r green:&g blue:&b alpha:&a];
    _shade.backgroundColor = [UIColor colorWithRed:r * 0.6 + (dark ? 0.02 : 0.6) * 0.4 green:g * 0.6 + (dark ? 0.02 : 0.6) * 0.4 blue:b * 0.6 + (dark ? 0.02 : 0.6) * 0.4 alpha:0.72];
    _date.textColor = _clock.textColor = dark ? UIColor.whiteColor : UIColor.blackColor;
    _brightActive.backgroundColor = _brightThumb.backgroundColor = C(@"primary");
    _brightInactive.backgroundColor = [C(@"surface_effect_1") colorWithAlphaComponent:0.54];
    for (NSUInteger i = 0; i < 8; i++) {
        BOOL active = (i == 0);
        _tiles[i].backgroundColor = active ? C(@"primary") : [C(@"surface_effect_1") colorWithAlphaComponent:0.54];
        _icons[i].tintColor = active ? C(@"on_primary") : C(@"on_surface");
    }
    _wifiTitle.textColor = _wifiSub.textColor = C(@"on_primary");
    for (UIView *bar in _bars) bar.backgroundColor = [C(@"on_surface") colorWithAlphaComponent:0.3];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEMMMd" options:0 locale:NSLocale.currentLocale];
    NSDateFormatter *tf = [NSDateFormatter new];
    tf.dateFormat = [[[NSDateFormatter dateFormatFromTemplate:@"jm" options:0 locale:NSLocale.currentLocale] stringByReplacingOccurrencesOfString:@"a" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    _date.text = [df stringFromDate:NSDate.date];
    _clock.text = [tf stringFromDate:NSDate.date];
    [self setNeedsLayout];
}
@end

#pragma mark - Controller

@implementation LQSColorsViewController {
    LQSThemePreview *_preview;
    UIView *_panel;
    UIButton *_close, *_apply;
    UILabel *_title;
    // landing
    UILabel *_sectionTitle, *_darkLabel;
    UIButton *_paletteButton;
    UISwitch *_darkSwitch;
    UIScrollView *_swatchScroll;
    NSMutableArray<UIControl *> *_swatches;
    UIView *_divider;
    // freeform / variant
    UILabel *_selectLabel;
    LQSHueSlider *_slider;
    NSMutableArray<UIControl *> *_variants;
    UIButton *_cancel, *_confirm;
    LQSColorsMode _mode;
    // state
    NSArray<NSNumber *> *_wallpaperSeeds;
    NSArray<NSNumber *> *_seeds;   // current selection (single seed per option, ThemePicker)
    NSString *_style;
    NSString *_source;             // "wallpaper" | "freeform"
    double _hue;
    NSArray<NSNumber *> *_savedSeeds;
    NSString *_savedStyle, *_savedSource;
    // editor snapshots for cancel
    NSArray<NSNumber *> *_editSeeds;
    NSString *_editStyle;
    NSDictionary<NSString *, NSNumber *> *_scheme;
}

- (instancetype)init {
    if ((self = [super init])) {
        _themePath = @"/var/mobile/Library/MaterialYou/theme.json";
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (BOOL)isDark { return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark; }
- (UIColor *)c:(NSString *)k { return _scheme[k] ? ARGB(_scheme[k]) : UIColor.grayColor; }

- (void)loadSaved {
    NSData *d = [NSData dataWithContentsOfFile:self.themePath];
    NSDictionary *t = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    _savedSeeds = [t[@"seeds"] isKindOfClass:NSArray.class] ? t[@"seeds"] : nil;
    _savedStyle = [t[@"style"] isKindOfClass:NSString.class] ? t[@"style"] : @"tonal_spot";
    _savedSource = [t[@"source"] isKindOfClass:NSString.class] ? t[@"source"] : @"wallpaper";
    _hue = [t[@"hue"] respondsToSelector:@selector(doubleValue)] ? [t[@"hue"] doubleValue] : 180;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.wallpaper) self.wallpaper = [LQSWallpaper currentImage];
    _wallpaperSeeds = self.wallpaper ? [LQSMonet seedColorsFromImage:self.wallpaper] : @[@((int)0xFF1B6EF3)];
    [self loadSaved];
    _source = _savedSource;
    _style = _savedStyle;
    _seeds = _savedSeeds.count ? _savedSeeds : @[_wallpaperSeeds.firstObject];

    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeBack:)];
    edge.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edge];
    _preview = [LQSThemePreview new];
    _preview.wallpaper = self.wallpaper;
    [self.view addSubview:_preview];

    _close = [self roundButton:@"ic_close" action:@selector(closeTapped)];
    _title = [UILabel new];
    _title.text = T(@"title");
    _title.font = [LQSTheme sansWithSize:22 weight:400]; // titleLarge
    [self.view addSubview:_title];
    _apply = [UIButton buttonWithType:UIButtonTypeCustom];
    _apply.titleLabel.font = [LQSTheme sansWithSize:14 weight:500];
    [_apply setTitle:T(@"apply") forState:UIControlStateNormal];
    _apply.layer.cornerRadius = 20;
    [_apply addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_apply];

    _panel = [UIView new];
    _panel.layer.cornerRadius = 28;
    [self.view addSubview:_panel];
    _sectionTitle = [UILabel new];
    _sectionTitle.text = T(@"wallpaper");
    _sectionTitle.font = [LQSTheme sansWithSize:14 weight:500];
    [_panel addSubview:_sectionTitle];
    _paletteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_paletteButton setImage:[LQSVectorIcon imageNamed:@"ic_palette" side:20] ?: [LQSVectorIcon imageNamed:@"ic_brightness_full" side:20] forState:UIControlStateNormal];
    _paletteButton.layer.cornerRadius = 18;
    _paletteButton.accessibilityLabel = T(@"custom");
    [_paletteButton addTarget:self action:@selector(openFreeform) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_paletteButton];
    _swatchScroll = [UIScrollView new];
    _swatchScroll.showsHorizontalScrollIndicator = NO;
    _swatchScroll.clipsToBounds = NO;
    [_panel addSubview:_swatchScroll];
    _divider = [UIView new];
    _divider.layer.cornerRadius = 1;
    [_swatchScroll addSubview:_divider];
    _darkLabel = [UILabel new];
    _darkLabel.text = T(@"dark");
    _darkLabel.font = [LQSTheme sansWithSize:16 weight:400];
    [_panel addSubview:_darkLabel];
    _darkSwitch = [UISwitch new];
    _darkSwitch.on = [self isDark];
    [_darkSwitch addTarget:self action:@selector(darkToggled) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:_darkSwitch];

    _selectLabel = [UILabel new];
    _selectLabel.text = T(@"select");
    _selectLabel.font = [LQSTheme sansWithSize:16 weight:500];
    _selectLabel.textAlignment = NSTextAlignmentCenter;
    [_panel addSubview:_selectLabel];
    _slider = [LQSHueSlider new];
    _slider.hue = _hue;
    [_slider addTarget:self action:@selector(hueChanged) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:_slider];
    _variants = [NSMutableArray array];
    for (NSString *st in Styles()) {
        UIControl *v = [UIControl new];
        v.accessibilityIdentifier = st;
        v.accessibilityLabel = T(st);
        UIView *disc = [UIView new]; disc.tag = 1; disc.userInteractionEnabled = NO; disc.clipsToBounds = YES;
        CAGradientLayer *grad = [CAGradientLayer layer]; grad.startPoint = CGPointMake(0, 0); grad.endPoint = CGPointMake(1, 1);
        [disc.layer addSublayer:grad];
        [v addSubview:disc];
        UILabel *l = [UILabel new]; l.tag = 2; l.text = T(st); l.font = [LQSTheme sansWithSize:12 weight:500]; l.textAlignment = NSTextAlignmentCenter;
        [v addSubview:l];
        [v addTarget:self action:@selector(variantTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:v];
        [_variants addObject:v];
    }
    _cancel = [self pillButton:@"ic_close" action:@selector(editorCancel)];
    _confirm = [self pillButton:@"ic_check" action:@selector(editorConfirm)];
    _swatches = [NSMutableArray array];
    [self buildSwatches];
    _mode = LQSColorsModeLanding;
    [self recompute];
}

- (UIButton *)roundButton:(NSString *)icon action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[LQSVectorIcon imageNamed:icon side:24] forState:UIControlStateNormal];
    b.layer.cornerRadius = 20;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}
// DrillDownFloatingSheet: 72x56dp buttons, 8dp apart, secondaryContainer / primary, 24dp icons.
- (UIButton *)pillButton:(NSString *)icon action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[LQSVectorIcon imageNamed:icon side:24] forState:UIControlStateNormal];
    b.layer.cornerRadius = 28;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (void)buildSwatches {
    for (UIView *v in _swatches) [v removeFromSuperview];
    [_swatches removeAllObjects];
    NSMutableArray *options = [NSMutableArray array]; // @[source, seed]
    if ([_savedSource isEqualToString:@"freeform"] && _savedSeeds.count) [options addObject:@[@"freeform", _savedSeeds.firstObject]]; // freeform first
    for (NSNumber *s in [_wallpaperSeeds subarrayWithRange:NSMakeRange(0, MIN(4, _wallpaperSeeds.count))]) [options addObject:@[@"wallpaper", s]];
    for (NSArray *o in options) {
        UIControl *c = [UIControl new];
        c.accessibilityIdentifier = o[0];
        c.tag = [o[1] intValue];
        UIView *ring = [UIView new]; ring.tag = 1; ring.userInteractionEnabled = NO;
        UIView *disc = [UIView new]; disc.tag = 2; disc.userInteractionEnabled = NO;
        UIView *badge = [UIView new]; badge.tag = 3; badge.userInteractionEnabled = NO;
        UIImageView *pen = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:@"ic_edit" side:16]];
        pen.tag = 4; pen.contentMode = UIViewContentModeCenter;
        [badge addSubview:pen];
        [c addSubview:ring]; [c addSubview:disc]; [c addSubview:badge];
        [c addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        c.accessibilityLabel = [o[0] isEqualToString:@"freeform"] ? T(@"custom") : T(@"wallpaper");
        [_swatchScroll addSubview:c];
        [_swatches addObject:c];
    }
}

- (BOOL)swatchSelected:(UIControl *)c {
    return [c.accessibilityIdentifier isEqualToString:_source] && _seeds.count && _seeds.firstObject.intValue == (int)c.tag;
}

#pragma mark - Recolor

- (void)recompute {
    _scheme = [LQSMonet schemeForSeeds:_seeds style:_style dark:[self isDark]];
    [_preview applyScheme:_scheme dark:[self isDark]];
    UIColor *(^C)(NSString *) = ^UIColor *(NSString *k) { return [self c:k]; };
    [UIView animateWithDuration:0.3 animations:^{
        self.view.backgroundColor = C(@"surface_container");
        self->_panel.backgroundColor = C(@"surface_bright");
        self->_close.backgroundColor = C(@"surface_container_highest");
        self->_close.tintColor = C(@"on_surface");
        self->_title.textColor = C(@"on_surface");
        BOOL changed = [self isChanged];
        self->_apply.enabled = changed;
        self->_apply.backgroundColor = changed ? C(@"primary") : [C(@"on_surface") colorWithAlphaComponent:0.1];
        [self->_apply setTitleColor:changed ? C(@"on_primary") : [C(@"on_surface") colorWithAlphaComponent:0.38] forState:UIControlStateNormal];
        self->_sectionTitle.textColor = C(@"on_surface");
        self->_paletteButton.backgroundColor = C(@"surface_container_high");
        self->_paletteButton.tintColor = C(@"on_surface");
        self->_divider.backgroundColor = C(@"outline_variant");
        self->_darkLabel.textColor = C(@"on_surface");
        self->_darkSwitch.onTintColor = C(@"primary");
        self->_selectLabel.textColor = C(@"on_surface");
        self->_slider.thumbColor = C(@"primary");
        self->_cancel.backgroundColor = C(@"secondary_container");
        self->_cancel.tintColor = C(@"on_secondary_container");
        self->_confirm.backgroundColor = C(@"primary");
        self->_confirm.tintColor = C(@"on_primary");
    }];
    BOOL dark = [self isDark];
    for (UIControl *c in _swatches) {
        int sw = [LQSMonet swatchColorForSeed:(int)c.tag style:@"tonal_spot" dark:dark];
        [c viewWithTag:2].backgroundColor = ARGB(@((unsigned)sw));
        BOOL sel = [self swatchSelected:c];
        UIView *ring = [c viewWithTag:1];
        ring.layer.borderColor = C(@"primary").CGColor;
        ring.layer.borderWidth = sel ? 3 : 0;
        UIView *badge = [c viewWithTag:3];
        badge.hidden = !sel;
        badge.backgroundColor = C(@"surface_bright");
        [badge viewWithTag:4].tintColor = C(@"on_primary_fixed_variant");
    }
    for (UIControl *v in _variants) {
        NSString *st = v.accessibilityIdentifier;
        NSDictionary *vs = [LQSMonet schemeForSeeds:_seeds style:st dark:dark];
        UIView *disc = [v viewWithTag:1];
        CAGradientLayer *g = (CAGradientLayer *)disc.layer.sublayers.firstObject;
        // ColorVariantPicker: SPRITZ secondaryFixed/secondaryFixed/primaryFixed, others tertiaryFixed/secondaryFixed/primaryFixed.
        NSString *first = [st isEqualToString:@"neutral"] ? @"secondary_fixed" : @"tertiary_fixed";
        g.colors = @[(id)ARGB(vs[first]).CGColor, (id)ARGB(vs[@"secondary_fixed"]).CGColor, (id)ARGB(vs[@"primary_fixed"]).CGColor];
        BOOL sel = [st isEqualToString:_style];
        disc.layer.borderColor = C(@"on_surface").CGColor;
        disc.layer.borderWidth = sel ? 3 : 0;
        UILabel *l = (UILabel *)[v viewWithTag:2];
        l.textColor = C(@"on_surface");
        l.font = [LQSTheme sansWithSize:12 weight:sel ? 700 : 500];
        v.alpha = 1;
    }
    [self.view setNeedsLayout];
}

- (BOOL)isChanged {
    BOOL sameSeed = _savedSeeds.count && _seeds.count && _savedSeeds.firstObject.intValue == _seeds.firstObject.intValue;
    return !(sameSeed && [_savedStyle isEqualToString:_style]);
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat w = b.size.width, top = self.view.safeAreaInsets.top + 8, bottom = b.size.height - self.view.safeAreaInsets.bottom;
    _close.frame = CGRectMake(16, top, 40, 40);
    _title.frame = CGRectMake(72, top, 160, 40);
    CGSize as = [_apply sizeThatFits:CGSizeMake(200, 40)];
    _apply.frame = CGRectMake(w - 16 - as.width - 32, top, as.width + 32, 40);
    BOOL landing = _mode == LQSColorsModeLanding;
    CGFloat panelH = landing ? 20 + 20 + 12 + 70 + 16 + 40 + 16 : (_mode == LQSColorsModeFreeform ? 20 + 24 + 16 + 44 + 20 : 20 + 68 + 22 + 20);
    CGFloat buttonsH = landing ? 0 : 56 + 16;
    CGFloat panelY = bottom - 16 - buttonsH - panelH;
    _panel.frame = CGRectMake(16, panelY, w - 32, panelH);
    CGFloat previewTop = landing ? CGRectGetMaxY(_close.frame) + 16 : top;
    CGFloat ph = panelY - 16 - previewTop, pw = MIN(w * 0.62, ph / 2.05);
    _preview.frame = CGRectMake((w - pw) / 2, previewTop + (ph - pw * 2.05) / 2, pw, pw * 2.05);
    _close.hidden = _title.hidden = _apply.hidden = !landing;
    CGFloat iw = _panel.bounds.size.width - 40;
    // landing
    for (UIView *v in @[_sectionTitle, _paletteButton, _swatchScroll, _darkLabel, _darkSwitch]) v.hidden = !landing;
    _sectionTitle.frame = CGRectMake(20, 16, iw - 52, 28);
    _paletteButton.frame = CGRectMake(20 + iw - 40, 10, 40, 40); // centred on the title row, right edge = switch edge
    _paletteButton.layer.cornerRadius = 20;
    _swatchScroll.frame = CGRectMake(20, 52, iw, 70);
    CGFloat x = 0;
    NSUInteger i = 0;
    BOOL freeformFirst = _swatches.count && [_swatches.firstObject.accessibilityIdentifier isEqualToString:@"freeform"];
    for (UIControl *c in _swatches) {
        if (i == 1 && freeformFirst) { _divider.frame = CGRectMake(x + 2, 21, 2, 28); x += 12; } // divider 12x28dp
        c.frame = CGRectMake(x, 0, 70, 70);
        [c viewWithTag:1].frame = CGRectMake(1, 1, 68, 68);
        [c viewWithTag:1].layer.cornerRadius = 34;
        [c viewWithTag:2].frame = CGRectMake(8, 8, 54, 54);
        [c viewWithTag:2].layer.cornerRadius = 27;
        UIView *badge = [c viewWithTag:3];
        badge.frame = CGRectMake(70 - 26, -2, 28, 28);
        badge.layer.cornerRadius = 14;
        [badge viewWithTag:4].frame = badge.bounds;
        x += 70 + 4;
        i++;
    }
    _divider.hidden = !freeformFirst;
    _swatchScroll.contentSize = CGSizeMake(x, 70);
    _darkLabel.frame = CGRectMake(20, 52 + 70 + 16, iw - 60, 40);
    _darkSwitch.frame = CGRectMake(20 + iw - 51, 52 + 70 + 16 + 4, 51, 31);
    // freeform
    _selectLabel.hidden = _slider.hidden = _mode != LQSColorsModeFreeform;
    _selectLabel.frame = CGRectMake(20, 20, iw, 24);
    _slider.frame = CGRectMake(20, 20 + 24 + 16, iw, 44);
    // variants: 68dp discs, labels 3dp below
    CGFloat vw = iw / 4;
    for (NSUInteger k = 0; k < _variants.count; k++) {
        UIControl *v = _variants[k];
        v.hidden = _mode != LQSColorsModeVariant;
        v.frame = CGRectMake(20 + k * vw, 20, vw, 68 + 22);
        UIView *disc = [v viewWithTag:1];
        disc.frame = CGRectMake((vw - 68) / 2, 0, 68, 68);
        disc.layer.cornerRadius = 34;
        disc.layer.sublayers.firstObject.frame = disc.bounds;
        [v viewWithTag:2].frame = CGRectMake(0, 68 + 3, vw, 18);
    }
    _cancel.hidden = _confirm.hidden = landing;
    _cancel.frame = CGRectMake(w / 2 - 4 - 72, bottom - 16 - 56, 72, 56);
    _confirm.frame = CGRectMake(w / 2 + 4, bottom - 16 - 56, 72, 56);
}

- (void)setMode:(LQSColorsMode)mode {
    _mode = mode;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    } completion:nil];
}

#pragma mark - Actions

- (void)tick { static UIImpactFeedbackGenerator *g; if (!g) g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [g impactOccurred]; }

- (void)swatchTapped:(UIControl *)c {
    [self tick];
    if ([self swatchSelected:c]) { [self openVariant]; return; } // pencil badge: theme style editor
    _source = c.accessibilityIdentifier;
    _seeds = @[@((int)c.tag)];
    if ([_source isEqualToString:@"wallpaper"]) _style = @"tonal_spot"; // wallpaper options default TONAL_SPOT
    [self recompute];
}

- (void)openFreeform {
    [self tick];
    _editSeeds = _seeds; _editStyle = _style;
    if (![_source isEqualToString:@"freeform"]) _slider.hue = [LQSMonet hueOfColor:_seeds.firstObject.intValue];
    [self setMode:LQSColorsModeFreeform];
    [self hueChanged];
}

- (void)openVariant {
    _editSeeds = _seeds; _editStyle = _style;
    [self setMode:LQSColorsModeVariant];
    [self recompute];
}

- (void)hueChanged {
    _hue = _slider.hue;
    _seeds = @[@([LQSMonet freeformSeedForHue:_hue])];
    _source = @"freeform";
    [self recompute];
}

- (void)variantTapped:(UIControl *)v {
    [self tick];
    _style = v.accessibilityIdentifier;
    [self recompute];
}

- (void)editorCancel {
    [self tick];
    _seeds = _editSeeds; _style = _editStyle;
    _source = _savedSource;
    if (_seeds.count && ![_wallpaperSeeds containsObject:_seeds.firstObject] && _savedSeeds.count) _source = @"freeform";
    [self setMode:LQSColorsModeLanding];
    [self recompute];
}

- (void)editorConfirm {
    [self tick];
    if (_mode == LQSColorsModeFreeform) {
        // Keep the chosen colour as the first ("Your colors") swatch.
        _savedSource = @"freeform";
        NSArray *keepSaved = _savedSeeds;
        _savedSeeds = _seeds;
        [self buildSwatches];
        _savedSeeds = keepSaved;
    }
    [self setMode:LQSColorsModeLanding];
    [self recompute];
}

- (void)darkToggled {
    [self tick];
    // Same switch as the Dark theme tile: iOS appearance (UIUserInterfaceStyleArbiter).
    Class arb = NSClassFromString(@"UIUserInterfaceStyleArbiter");
    id a = [arb respondsToSelector:NSSelectorFromString(@"sharedInstance")] ? ((id (*)(id, SEL))objc_msgSend)(arb, NSSelectorFromString(@"sharedInstance")) : nil;
    if ([a respondsToSelector:NSSelectorFromString(@"toggleCurrentStyle")]) ((void (*)(id, SEL))objc_msgSend)(a, NSSelectorFromString(@"toggleCurrentStyle"));
    else self.overrideUserInterfaceStyle = _darkSwitch.on ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    _darkSwitch.on = [self isDark];
    [self recompute];
}

- (void)applyTapped {
    [self tick];
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    t[@"seeds"] = _seeds;
    t[@"style"] = _style;
    t[@"source"] = _source;
    t[@"hue"] = @(_hue);
    t[@"colors"] = [LQSMonet systemColorsForSeeds:_seeds style:_style];
    NSData *d = [NSJSONSerialization dataWithJSONObject:t options:0 error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.themePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:self.themePath atomically:YES];
    notify_post(LQSThemeChangedNotification.UTF8String);
    _savedSeeds = _seeds; _savedStyle = _style; _savedSource = _source;
    [self recompute];
}

- (UINavigationController *)findNav {
    for (UIResponder *r = self; r; r = r.nextResponder) {
        if ([r isKindOfClass:UINavigationController.class]) return (UINavigationController *)r;
        if ([r isKindOfClass:UIViewController.class] && ((UIViewController *)r).navigationController) return ((UIViewController *)r).navigationController;
    }
    return nil;
}

- (void)closeTapped {
    [self tick];
    // Settings (iOS 16) nests navigation controllers inside a collapsed split view: pop on the
    // first one that has something to pop.
    for (UINavigationController *nav = [self findNav]; nav; nav = nav.navigationController) {
        if (nav.viewControllers.count > 1) { [nav setNavigationBarHidden:NO animated:YES]; [nav popViewControllerAnimated:YES]; return; }
    }
    UISplitViewController *split = nil;
    for (UIResponder *r = self; r; r = r.nextResponder) if ([r isKindOfClass:UISplitViewController.class]) { split = (UISplitViewController *)r; break; }
    UINavigationController *primary = [split.viewControllers.firstObject isKindOfClass:UINavigationController.class] ? split.viewControllers.firstObject : nil;
    if (primary.viewControllers.count > 1) { [primary setNavigationBarHidden:NO animated:YES]; [primary popToRootViewControllerAnimated:YES]; return; }
    NSLog(@"[MaterialYou] close: no navigation stack found (nav=%@ split=%@)", [self findNav], split);
    UIViewController *top = self;
    while (top.parentViewController) top = top.parentViewController;
    [top dismissViewControllerAnimated:YES completion:nil];
}

// Edge swipe back (the system one is unreliable with the bar hidden inside Settings).
- (void)edgeBack:(UIScreenEdgePanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateEnded && [g translationInView:self.view].x > 60) [self closeTapped];
}

@end
