#import "LQSMediaCard.h"
#import "LQSMedia.h"
#import "LQSTheme.h"
#import "LQSViews.h"
#import "LQSVectorIcon.h"


// Port of media/controls/ui/drawable/SquigglyProgress.kt: wavelength 20dp, amplitude
// 1.5dp, phase speed 8dp/s, stroke 2dp (dimens.xml:1356-1359); height animates in
// over 800ms EMPHASIZED_DECELERATE (60ms delay) when playing, out over 550ms.
@interface LQSSquiggly : UIView
@property (nonatomic) CGFloat progress;
@property (nonatomic) BOOL animating;
@property (nonatomic, strong) UIColor *color;
@end
@implementation LQSSquiggly {
    CADisplayLink *_link;
    CFTimeInterval _last, _hStart;
    CGFloat _phase, _height, _hFrom, _hTo, _hDur, _hDelay;
}
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = UIColor.clearColor; _color = UIColor.whiteColor; } return self; }
- (void)setProgress:(CGFloat)p { _progress = MAX(0, MIN(1, p)); [self setNeedsDisplay]; }
- (void)setAnimating:(BOOL)a {
    if (a == _animating && _link) return;
    _animating = a;
    _hFrom = _height; _hTo = a ? 1 : 0; _hDur = a ? 0.8 : 0.55; _hDelay = a ? 0.06 : 0; _hStart = CACurrentMediaTime();
    _last = CACurrentMediaTime();
    if (!_link) { _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)]; [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes]; }
}
- (void)didMoveToWindow { [super didMoveToWindow]; if (!self.window) { [_link invalidate]; _link = nil; } else if (_animating || _height > 0) { BOOL a = _animating; _animating = !a; self.animating = a; } }
- (void)step:(CADisplayLink *)l {
    CFTimeInterval now = CACurrentMediaTime();
    if (_animating) { _phase = fmod(_phase + (now - _last) * 8.0, 20.0); }
    _last = now;
    CGFloat f = MAX(0, MIN(1, (now - _hStart - _hDelay) / _hDur));
    CGFloat e = _hTo > _hFrom ? LQSCubic(0.05, 0.7, 0.1, 1, f) : LQSCubic(0, 0, 0, 1, f);
    _height = _hFrom + (_hTo - _hFrom) * e;
    if (!_animating && f >= 1) { [_link invalidate]; _link = nil; }
    [self setNeedsDisplay];
}
static CGFloat LerpInvSat(CGFloat a, CGFloat b, CGFloat v) { return MAX(0, MIN(1, (v - a) / (b - a))); }
- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat W = self.bounds.size.width, amp = 1.5, wl = 20, stroke = 2;
    CGFloat total = W * _progress;
    CGFloat waveProg = W * (_progress > 0.6 ? _progress : 0.2 + (0.6 - 0.2) * (_progress / 0.6));
    CGFloat start = -_phase - wl / 2, len = 1.5 * wl;
    CGFloat (^A)(CGFloat, CGFloat) = ^CGFloat(CGFloat x, CGFloat sign) {
        return sign * self->_height * amp * LerpInvSat(waveProg + len / 2, waveProg - len / 2, x);
    };
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(start, 0)];
    CGFloat x = start, sign = 1, cur = A(x, sign), dist = wl / 2;
    while (x < W) { sign = -sign; CGFloat nx = x + dist, mx = x + dist / 2, na = A(nx, sign);
        [path addCurveToPoint:CGPointMake(nx, na) controlPoint1:CGPointMake(mx, cur) controlPoint2:CGPointMake(mx, na)]; cur = na; x = nx; }
    path.lineWidth = stroke; path.lineCapStyle = kCGLineCapRound;
    CGFloat clip = amp + stroke;
    CGContextTranslateCTM(ctx, 0, self.bounds.size.height / 2);
    CGContextSaveGState(ctx); CGContextClipToRect(ctx, CGRectMake(0, -clip, total, 2 * clip)); [_color setStroke]; [path stroke]; CGContextRestoreGState(ctx);
    // Unplayed part: straight line (transitionEnabled = false path), DISABLED_ALPHA 77.
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(total + stroke, 0)];
    [line addLineToPoint:CGPointMake(W, 0)];
    line.lineWidth = stroke; line.lineCapStyle = kCGLineCapRound;
    [[_color colorWithAlphaComponent:77 / 255.0] setStroke];
    if (W - total > stroke) [line stroke];
    // media_seekbar_thumb: 4x16dp rounded bar at the play position.
    [_color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(MIN(MAX(0, total - 2), W - 4), -8, 4, 16) cornerRadius:2] fill];
}
@end

@implementation LQSMediaCard {
    UIImageView *_art;
    UIView *_scrim;
    LQSSquiggly *_squiggly;
    NSString *_lastTitle;
    UIImageView *_playBg, *_playGlyph;
    CADisplayLink *_avdLink;
    CFTimeInterval _avdStart;
    NSString *_avdGlyph, *_avdBg;
    CFTimeInterval _optimisticUntil;
    BOOL _seeking;
    BOOL _lastPlaying;
    UILabel *_title, *_artist, *_app;
    UIButton *_play, *_prev, *_next;
    NSTimer *_timer;
}
+ (CGFloat)height { return 128; } // qs_media_session_height_collapsed

- (UIButton *)button:(NSString *)icon sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[LQSVectorIcon imageNamed:icon side:([icon containsString:@"prev"] || [icon containsString:@"next"]) ? 16 : 24] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 28;
        _art = [UIImageView new];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_art];
        _scrim = [UIView new];
        [self addSubview:_scrim];
        _app = [UILabel new]; _app.font = [LQSTheme sansWithSize:12 weight:500];
        _title = [UILabel new]; _title.font = [LQSTheme sansWithSize:16 weight:500];
        _artist = [UILabel new]; _artist.font = [LQSTheme sansWithSize:14 weight:400];
        for (UILabel *l in @[_app, _title, _artist]) { l.textColor = UIColor.whiteColor; [self addSubview:l]; }
        _app.alpha = 0.8; _artist.alpha = 0.8;
        _prev = [self button:@"ic_media_prev" sel:@selector(prevTapped)];
        _next = [self button:@"ic_media_next" sel:@selector(nextTapped)];
        _play = [UIButton buttonWithType:UIButtonTypeCustom];
        [_play addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_play];
        _playBg = [UIImageView new]; _playGlyph = [UIImageView new];
        _playBg.userInteractionEnabled = _playGlyph.userInteractionEnabled = NO;
        _playGlyph.contentMode = UIViewContentModeCenter;
        _playBg.contentMode = UIViewContentModeCenter; // square render, keep the vector aspect
        [_play addSubview:_playBg]; [_play addSubview:_playGlyph];
        _squiggly = [LQSSquiggly new];
        [self addSubview:_squiggly];
        // Seek by dragging / tapping the bar (SeekBarViewModel: seek on release).
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekPan:)];
        pan.delegate = (id<UIGestureRecognizerDelegate>)self;
        [_squiggly addGestureRecognizer:pan];
        [_squiggly addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(seekPan:)]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update) name:LQSMediaChangedNotification object:nil];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (self.window) {
        [[LQSMedia shared] start];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self update];
    }
}

- (BOOL)hasMedia { return [LQSMedia shared].hasMedia; }

- (void)update {
    LQSMedia *m = [LQSMedia shared];
    BOOL trackChanged = m.title.length && ![m.title isEqualToString:(_lastTitle ?: @"")];
    if (m.title.length) _lastTitle = m.title;
    void (^content)(void) = ^{
        // MediaRemote briefly reports no artwork while play state changes: keep the old one.
        if (m.artwork || trackChanged) self->_art.image = m.artwork ?: self->_art.image;
        self->_scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        self->_title.text = m.title ?: @"";
        self->_artist.text = m.artist ?: @"";
        self->_app.text = m.appName ?: @"";
    };
    if (trackChanged && self.window) [UIView transitionWithView:self->_title.superview == self ? self->_art : self duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:content completion:nil];
    else content();
    _playBg.tintColor = [LQSTheme primary];
    _playGlyph.tintColor = [LQSTheme onPrimary];
    if (!_playGlyph.image) [self setRestPlaying:m.playing];
    else if (m.playing != _lastPlaying && CACurrentMediaTime() > _optimisticUntil) [self showPlaying:m.playing]; // stale state right after a tap is ignored
    [self tick];
    if (self.onChange) self.onChange();
}

// Media3ActionFactory: not playing -> ic_media_play_button (+ _container), playing ->
// ic_media_pause_button. They are AnimatedVectorDrawables shown at their first frame
// and started on change: play_button morphs play -> pause, pause_button pause -> play
// (517 ms), the containers morph the 88x56dp pill shape alongside.
- (CGSize)playSize { return CGSizeMake(88 * 0.9, 56 * 0.9); } // ic_media_*_container 88x56dp, 0.9 for the compact card (assumption)
- (void)setRestPlaying:(BOOL)playing {
    _lastPlaying = playing;
    [_avdLink invalidate]; _avdLink = nil;
    CGSize sz = [self playSize];
    NSString *g = playing ? @"ic_media_pause_button" : @"ic_media_play_button";
    _playGlyph.image = [LQSVectorIcon frameNamed:g side:24 atTime:0];
    _playBg.image = [LQSVectorIcon frameNamed:[g stringByAppendingString:@"_container"] side:sz.width atTime:0];
    _squiggly.animating = playing;
}
- (void)showPlaying:(BOOL)playing {
    if (playing == _lastPlaying && _playGlyph.image) return;
    BOOL wasPlaying = _lastPlaying;
    _lastPlaying = playing;
    _squiggly.animating = playing;
    _avdGlyph = wasPlaying ? @"ic_media_pause_button" : @"ic_media_play_button";
    _avdBg = [_avdGlyph stringByAppendingString:@"_container"];
    _avdStart = CACurrentMediaTime();
    [_avdLink invalidate];
    _avdLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(avdTick:)];
    [_avdLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)avdTick:(CADisplayLink *)l {
    NSTimeInterval t = CACurrentMediaTime() - _avdStart, d = MAX(0.05, [LQSVectorIcon animationDurationNamed:_avdGlyph]);
    if (t >= d) { [self setRestPlaying:_lastPlaying]; return; }
    _playGlyph.image = [LQSVectorIcon frameNamed:_avdGlyph side:24 atTime:t];
    UIImage *bg = [LQSVectorIcon frameNamed:_avdBg side:[self playSize].width atTime:t];
    if (bg) _playBg.image = bg;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:UIPanGestureRecognizer.class] || g.view != _squiggly) return YES;
    CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
    return fabs(v.x) > fabs(v.y); // vertical drags stay with the shade
}

- (void)seekPan:(UIGestureRecognizer *)g {
    LQSMedia *m = [LQSMedia shared];
    if (m.duration <= 0) return;
    CGFloat f = MAX(0, MIN(1, [g locationInView:_squiggly].x / MAX(1, _squiggly.bounds.size.width)));
    _seeking = YES;
    _squiggly.progress = f;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || [g isKindOfClass:UITapGestureRecognizer.class]) {
        [m seekTo:f * m.duration];
        LQSHapticTick();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self->_seeking = NO; [m refresh]; });
    }
}

- (void)tick {
    LQSMedia *m = [LQSMedia shared];
    if (_seeking) return;
    _squiggly.progress = m.duration > 0 ? MIN(1, m.elapsed / m.duration) : 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height, pad = 16;
    _art.frame = self.bounds;
    _scrim.frame = self.bounds;
    CGSize ps = [self playSize];
    _play.frame = CGRectMake(w - pad - ps.width, pad, ps.width, ps.height);
    _playBg.frame = _play.bounds;
    _playGlyph.frame = _play.bounds;
    _next.frame = CGRectMake(CGRectGetMinX(_play.frame) - 40, pad + 2, 40, 40);
    _prev.frame = CGRectMake(CGRectGetMinX(_next.frame) - 40, pad + 2, 40, 40);
    CGFloat tw = CGRectGetMinX(_prev.frame) - pad - 8;
    _app.frame = CGRectMake(pad, pad, tw, 16);
    _title.frame = CGRectMake(pad, pad + 18, tw, 22);
    _artist.frame = CGRectMake(pad, pad + 40, tw, 18);
    _squiggly.frame = CGRectMake(pad, h - 15 - 16, w - 2 * pad, 16); // seekbar vertical padding 15dp, thumb 16dp
    [self tick];
}

- (void)playTapped {
    LQSHapticTick();
    [[LQSMedia shared] togglePlayPause];
    [self showPlaying:!_lastPlaying]; // optimistic, corrected by MediaRemote
    _optimisticUntil = CACurrentMediaTime() + 1.5;
    for (NSNumber *d in @[@1.6]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[LQSMedia shared] refresh]; });
}
- (void)prevTapped { LQSHapticTick(); [[LQSMedia shared] previous]; }
- (void)nextTapped { LQSHapticTick(); [[LQSMedia shared] next]; }
@end
