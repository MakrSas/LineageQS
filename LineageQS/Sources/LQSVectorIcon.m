#import "LQSVectorIcon.h"

static NSString *gResourceDirectory;
static NSCache *gImageCache;

#pragma mark - Path parsing

typedef struct {
    const char *s;
    size_t i, n;
} LQSScanner;

static void SkipSeparators(LQSScanner *sc) {
    while (sc->i < sc->n) {
        char c = sc->s[sc->i];
        if (c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r') sc->i++;
        else break;
    }
}

static BOOL ReadNumber(LQSScanner *sc, CGFloat *out) {
    SkipSeparators(sc);
    size_t start = sc->i;
    if (sc->i < sc->n && (sc->s[sc->i] == '-' || sc->s[sc->i] == '+')) sc->i++;
    BOOL digits = NO, dot = NO;
    while (sc->i < sc->n) {
        char c = sc->s[sc->i];
        if (c >= '0' && c <= '9') { digits = YES; sc->i++; }
        else if (c == '.' && !dot) { dot = YES; sc->i++; }
        else break;
    }
    if (digits && sc->i < sc->n && (sc->s[sc->i] == 'e' || sc->s[sc->i] == 'E')) {
        size_t save = sc->i++;
        if (sc->i < sc->n && (sc->s[sc->i] == '-' || sc->s[sc->i] == '+')) sc->i++;
        BOOL expDigits = NO;
        while (sc->i < sc->n && sc->s[sc->i] >= '0' && sc->s[sc->i] <= '9') { sc->i++; expDigits = YES; }
        if (!expDigits) sc->i = save;
    }
    if (!digits) { sc->i = start; return NO; }
    char buf[64];
    size_t len = MIN(sc->i - start, sizeof(buf) - 1);
    memcpy(buf, sc->s + start, len);
    buf[len] = 0;
    *out = (CGFloat)strtod(buf, NULL);
    return YES;
}

// Arc flags may be written without separators ("a1 1 0 011 1").
static BOOL ReadFlag(LQSScanner *sc, CGFloat *out) {
    SkipSeparators(sc);
    if (sc->i < sc->n && (sc->s[sc->i] == '0' || sc->s[sc->i] == '1')) {
        *out = sc->s[sc->i] == '1';
        sc->i++;
        return YES;
    }
    return NO;
}

static void AddArc(CGMutablePathRef path, CGPoint p0, CGFloat rx, CGFloat ry, CGFloat angleDeg,
                   BOOL largeArc, BOOL sweep, CGPoint p1) {
    if (CGPointEqualToPoint(p0, p1)) return;
    rx = fabs(rx); ry = fabs(ry);
    if (rx == 0 || ry == 0) { CGPathAddLineToPoint(path, NULL, p1.x, p1.y); return; }
    CGFloat phi = angleDeg * M_PI / 180.0, cphi = cos(phi), sphi = sin(phi);
    CGFloat dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2;
    CGFloat x1p = cphi * dx + sphi * dy, y1p = -sphi * dx + cphi * dy;
    CGFloat lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) { CGFloat s = sqrt(lambda); rx *= s; ry *= s; }
    CGFloat num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    CGFloat den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    CGFloat coef = (den == 0) ? 0 : sqrt(MAX(0, num / den));
    if (largeArc == sweep) coef = -coef;
    CGFloat cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx;
    CGFloat cx = cphi * cxp - sphi * cyp + (p0.x + p1.x) / 2;
    CGFloat cy = sphi * cxp + cphi * cyp + (p0.y + p1.y) / 2;
    CGFloat ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    CGFloat vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
    CGFloat theta1 = atan2(uy, ux);
    CGFloat dtheta = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep && dtheta > 0) dtheta -= 2 * M_PI;
    else if (sweep && dtheta < 0) dtheta += 2 * M_PI;
    int segs = (int)ceil(fabs(dtheta) / (M_PI / 2));
    CGFloat delta = dtheta / segs;
    CGFloat t = 4.0 / 3.0 * tan(delta / 4);
    CGFloat th = theta1;
    for (int k = 0; k < segs; k++) {
        CGFloat c1 = cos(th), s1 = sin(th), c2 = cos(th + delta), s2 = sin(th + delta);
        CGPoint e1 = CGPointMake(c1 - t * s1, s1 + t * c1);
        CGPoint e2 = CGPointMake(c2 + t * s2, s2 - t * c2);
        CGPoint e3 = CGPointMake(c2, s2);
        CGPoint pts[3] = {e1, e2, e3};
        for (int j = 0; j < 3; j++) {
            CGFloat x = pts[j].x * rx, y = pts[j].y * ry;
            pts[j] = CGPointMake(cphi * x - sphi * y + cx, sphi * x + cphi * y + cy);
        }
        CGPathAddCurveToPoint(path, NULL, pts[0].x, pts[0].y, pts[1].x, pts[1].y, pts[2].x, pts[2].y);
        th += delta;
    }
}

static BOOL NextIsCommand(LQSScanner *sc) {
    SkipSeparators(sc);
    if (sc->i >= sc->n) return YES;
    char c = sc->s[sc->i];
    return (c >= 'A' && c <= 'Z' && c != 'E') || (c >= 'a' && c <= 'z' && c != 'e');
}

static CGPathRef NewPathFromCString(const char *str, size_t n) {
    CGMutablePathRef path = CGPathCreateMutable();
    LQSScanner sc = {str, 0, n};
    char cmd = 0;
    CGPoint cur = CGPointZero, start = CGPointZero, lastCtrl = CGPointZero;
    char prev = 0;
    while (1) {
        SkipSeparators(&sc);
        if (sc.i >= sc.n) break;
        char c = sc.s[sc.i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) { cmd = c; sc.i++; }
        else if (!cmd) { sc.i++; continue; } // stray token
        BOOL rel = (cmd >= 'a');
        char up = rel ? cmd - 32 : cmd;
        CGFloat v[7];
        switch (up) {
            case 'Z':
                CGPathCloseSubpath(path);
                cur = start;
                prev = 'Z';
                cmd = 0; // Z takes no arguments; next token must be a command
                continue;
            case 'M':
                if (!ReadNumber(&sc, &v[0]) || !ReadNumber(&sc, &v[1])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                cur = rel ? CGPointMake(cur.x + v[0], cur.y + v[1]) : CGPointMake(v[0], v[1]);
                CGPathMoveToPoint(path, NULL, cur.x, cur.y);
                start = cur;
                cmd = rel ? 'l' : 'L'; // implicit lineto after moveto
                break;
            case 'L':
                if (!ReadNumber(&sc, &v[0]) || !ReadNumber(&sc, &v[1])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                cur = rel ? CGPointMake(cur.x + v[0], cur.y + v[1]) : CGPointMake(v[0], v[1]);
                CGPathAddLineToPoint(path, NULL, cur.x, cur.y);
                break;
            case 'H':
                if (!ReadNumber(&sc, &v[0])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                cur.x = rel ? cur.x + v[0] : v[0];
                CGPathAddLineToPoint(path, NULL, cur.x, cur.y);
                break;
            case 'V':
                if (!ReadNumber(&sc, &v[0])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                cur.y = rel ? cur.y + v[0] : v[0];
                CGPathAddLineToPoint(path, NULL, cur.x, cur.y);
                break;
            case 'C': {
                for (int k = 0; k < 6; k++) if (!ReadNumber(&sc, &v[k])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                CGFloat ox = rel ? cur.x : 0, oy = rel ? cur.y : 0;
                CGPathAddCurveToPoint(path, NULL, ox + v[0], oy + v[1], ox + v[2], oy + v[3], ox + v[4], oy + v[5]);
                lastCtrl = CGPointMake(ox + v[2], oy + v[3]);
                cur = CGPointMake(ox + v[4], oy + v[5]);
                prev = 'C';
                continue;
            }
            case 'S': {
                for (int k = 0; k < 4; k++) if (!ReadNumber(&sc, &v[k])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                CGFloat ox = rel ? cur.x : 0, oy = rel ? cur.y : 0;
                CGPoint c1 = (prev == 'C') ? CGPointMake(2 * cur.x - lastCtrl.x, 2 * cur.y - lastCtrl.y) : cur;
                CGPathAddCurveToPoint(path, NULL, c1.x, c1.y, ox + v[0], oy + v[1], ox + v[2], oy + v[3]);
                lastCtrl = CGPointMake(ox + v[0], oy + v[1]);
                cur = CGPointMake(ox + v[2], oy + v[3]);
                prev = 'C';
                continue;
            }
            case 'Q': {
                for (int k = 0; k < 4; k++) if (!ReadNumber(&sc, &v[k])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                CGFloat ox = rel ? cur.x : 0, oy = rel ? cur.y : 0;
                CGPathAddQuadCurveToPoint(path, NULL, ox + v[0], oy + v[1], ox + v[2], oy + v[3]);
                lastCtrl = CGPointMake(ox + v[0], oy + v[1]);
                cur = CGPointMake(ox + v[2], oy + v[3]);
                prev = 'Q';
                continue;
            }
            case 'T': {
                for (int k = 0; k < 2; k++) if (!ReadNumber(&sc, &v[k])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                CGFloat ox = rel ? cur.x : 0, oy = rel ? cur.y : 0;
                CGPoint c1 = (prev == 'Q') ? CGPointMake(2 * cur.x - lastCtrl.x, 2 * cur.y - lastCtrl.y) : cur;
                CGPathAddQuadCurveToPoint(path, NULL, c1.x, c1.y, ox + v[0], oy + v[1]);
                lastCtrl = c1;
                cur = CGPointMake(ox + v[0], oy + v[1]);
                prev = 'Q';
                continue;
            }
            case 'A': {
                if (!ReadNumber(&sc, &v[0]) || !ReadNumber(&sc, &v[1]) || !ReadNumber(&sc, &v[2]) ||
                    !ReadFlag(&sc, &v[3]) || !ReadFlag(&sc, &v[4]) || !ReadNumber(&sc, &v[5]) || !ReadNumber(&sc, &v[6])) { if (NextIsCommand(&sc)) goto skipcmd; goto done; }
                CGPoint end = rel ? CGPointMake(cur.x + v[5], cur.y + v[6]) : CGPointMake(v[5], v[6]);
                AddArc(path, cur, v[0], v[1], v[2], v[3] != 0, v[4] != 0, end);
                cur = end;
                break;
            }
            default:
                cmd = 0;
                continue;
        }
        prev = up;
        continue;
    skipcmd:
        // Android PathParser accepts a command letter with no arguments
        // (e.g. Lottie-exported "...28.25c M31.94 ..."): it adds nothing.
        cmd = 0;
    }
done:
    return path;
}

#pragma mark - Trim (Android trimPathStart/End/Offset)

static void AppendFlattened(CGPathRef path, NSMutableArray<NSValue *> *pts, NSMutableArray<NSNumber *> *breaks) {
    __block CGPoint cur = CGPointZero, start = CGPointZero;
    CGPathApplyWithBlock(path, ^(const CGPathElement *e) {
        switch (e->type) {
            case kCGPathElementMoveToPoint:
                [breaks addObject:@(pts.count)];
                cur = start = e->points[0];
                [pts addObject:[NSValue valueWithCGPoint:cur]];
                break;
            case kCGPathElementAddLineToPoint:
                cur = e->points[0];
                [pts addObject:[NSValue valueWithCGPoint:cur]];
                break;
            case kCGPathElementAddQuadCurveToPoint:
                for (int k = 1; k <= 16; k++) {
                    CGFloat t = k / 16.0, u = 1 - t;
                    CGPoint p = CGPointMake(u * u * cur.x + 2 * u * t * e->points[0].x + t * t * e->points[1].x,
                                            u * u * cur.y + 2 * u * t * e->points[0].y + t * t * e->points[1].y);
                    [pts addObject:[NSValue valueWithCGPoint:p]];
                }
                cur = e->points[1];
                break;
            case kCGPathElementAddCurveToPoint:
                for (int k = 1; k <= 24; k++) {
                    CGFloat t = k / 24.0, u = 1 - t;
                    CGPoint p = CGPointMake(u * u * u * cur.x + 3 * u * u * t * e->points[0].x + 3 * u * t * t * e->points[1].x + t * t * t * e->points[2].x,
                                            u * u * u * cur.y + 3 * u * u * t * e->points[0].y + 3 * u * t * t * e->points[1].y + t * t * t * e->points[2].y);
                    [pts addObject:[NSValue valueWithCGPoint:p]];
                }
                cur = e->points[2];
                break;
            case kCGPathElementCloseSubpath:
                cur = start;
                [pts addObject:[NSValue valueWithCGPoint:cur]];
                break;
        }
    });
}

static CGPathRef NewTrimmedPath(CGPathRef path, CGFloat ts, CGFloat te, CGFloat to) {
    NSMutableArray<NSValue *> *pts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *breaks = [NSMutableArray array];
    AppendFlattened(path, pts, breaks);
    NSMutableSet *breakSet = [NSMutableSet setWithArray:breaks];
    CGFloat total = 0;
    NSMutableArray<NSNumber *> *cum = [NSMutableArray arrayWithObject:@0];
    for (NSUInteger k = 1; k < pts.count; k++) {
        CGPoint a = pts[k - 1].CGPointValue, b = pts[k].CGPointValue;
        if (![breakSet containsObject:@(k)]) total += hypot(b.x - a.x, b.y - a.y);
        [cum addObject:@(total)];
    }
    CGMutablePathRef out = CGPathCreateMutable();
    if (total <= 0) return out;
    CGFloat s = fmod(ts + to, 1.0), e = fmod(te + to, 1.0);
    if (te - ts >= 1.0) { s = 0; e = 1; }
    NSArray *ranges = (s <= e) ? @[@[@(s), @(e)]] : @[@[@(s), @1.0], @[@0.0, @(e)]];
    for (NSArray *r in ranges) {
        CGFloat a0 = [r[0] doubleValue] * total, a1 = [r[1] doubleValue] * total;
        BOOL pen = NO;
        for (NSUInteger k = 1; k < pts.count; k++) {
            if ([breakSet containsObject:@(k)]) { pen = NO; continue; }
            CGFloat l0 = cum[k - 1].doubleValue, l1 = cum[k].doubleValue;
            if (l1 < a0 || l0 > a1 || l1 == l0) continue;
            CGPoint p0 = pts[k - 1].CGPointValue, p1 = pts[k].CGPointValue;
            CGFloat f0 = MAX(0, (a0 - l0) / (l1 - l0)), f1 = MIN(1, (a1 - l0) / (l1 - l0));
            CGPoint q0 = CGPointMake(p0.x + (p1.x - p0.x) * f0, p0.y + (p1.y - p0.y) * f0);
            CGPoint q1 = CGPointMake(p0.x + (p1.x - p0.x) * f1, p0.y + (p1.y - p0.y) * f1);
            if (!pen) { CGPathMoveToPoint(out, NULL, q0.x, q0.y); pen = YES; }
            CGPathAddLineToPoint(out, NULL, q1.x, q1.y);
        }
    }
    return out;
}

#pragma mark - Rendering

static UIColor *(^gColorResolver)(NSString *ref);
static BOOL gColoredPass;

static UIColor *ResolveColor(id value) {
    if (![value isKindOfClass:NSString.class]) return UIColor.blackColor;
    NSString *s = value;
    if ([s hasPrefix:@"#"] && s.length == 9) {
        unsigned int argb = 0;
        [[NSScanner scannerWithString:[s substringFromIndex:1]] scanHexInt:&argb];
        return [UIColor colorWithRed:((argb >> 16) & 0xff) / 255.0 green:((argb >> 8) & 0xff) / 255.0 blue:(argb & 0xff) / 255.0 alpha:((argb >> 24) & 0xff) / 255.0];
    }
    UIColor *c = gColorResolver ? gColorResolver(s) : nil;
    return c ?: UIColor.whiteColor;
}

static CGFloat ColorAlpha(id value) {
    if (![value isKindOfClass:NSString.class]) return 1.0;
    NSString *s = value;
    if ([s hasPrefix:@"#"] && s.length == 9) {
        unsigned int argb = 0;
        [[NSScanner scannerWithString:[s substringFromIndex:1]] scanHexInt:&argb];
        return ((argb >> 24) & 0xff) / 255.0;
    }
    return 1.0; // unresolved theme reference: Android tints it anyway
}

static CGFloat Num(NSDictionary *d, NSString *key, CGFloat def) {
    id v = d[key];
    return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : def;
}

static void DrawNodes(CGContextRef ctx, NSArray *nodes) {
    for (NSDictionary *node in nodes) {
        NSString *type = node[@"type"];
        if ([type isEqualToString:@"group"]) {
            NSDictionary *t = node[@"transform"] ?: @{};
            CGFloat px = Num(t, @"pivotX", 0), py = Num(t, @"pivotY", 0);
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, Num(t, @"translateX", 0) + px, Num(t, @"translateY", 0) + py);
            CGContextRotateCTM(ctx, Num(t, @"rotation", 0) * M_PI / 180.0);
            CGContextScaleCTM(ctx, Num(t, @"scaleX", 1), Num(t, @"scaleY", 1));
            CGContextTranslateCTM(ctx, -px, -py);
            DrawNodes(ctx, node[@"children"]);
            CGContextRestoreGState(ctx);
        } else if ([type isEqualToString:@"clip"]) {
            NSString *d = node[@"d"];
            CGPathRef p = [LQSVectorIcon newPathFromString:d];
            if (p) {
                CGContextAddPath(ctx, p);
                CGContextClip(ctx); // applies to following siblings; group restore pops it
                CGPathRelease(p);
            }
        } else if ([type isEqualToString:@"path"]) {
            NSString *d = node[@"d"];
            CGPathRef base = [LQSVectorIcon newPathFromString:d];
            if (!base) continue;
            CGFloat ts = Num(node, @"trimPathStart", 0), te = Num(node, @"trimPathEnd", 1), to = Num(node, @"trimPathOffset", 0);
            BOOL trimmed = (ts != 0 || te != 1 || to != 0);
            if (node[@"fill"]) {
                CGFloat a = Num(node, @"fillAlpha", 1) * ColorAlpha(node[@"fill"]);
                if (a > 0.001) {
                    UIColor *fc = gColoredPass ? [ResolveColor(node[@"fill"]) colorWithAlphaComponent:a] : [UIColor colorWithWhite:0 alpha:a];
                    CGContextSetFillColorWithColor(ctx, fc.CGColor);
                    CGContextAddPath(ctx, base);
                    if ([node[@"fillType"] isEqualToString:@"evenOdd"]) CGContextEOFillPath(ctx);
                    else CGContextFillPath(ctx);
                }
            }
            CGFloat sw = Num(node, @"strokeWidth", 0);
            if (node[@"stroke"] && sw > 0) {
                CGFloat a = Num(node, @"strokeAlpha", 1) * ColorAlpha(node[@"stroke"]);
                CGPathRef sp = trimmed ? NewTrimmedPath(base, ts, te, to) : CGPathRetain(base);
                if (a > 0.001 && !(trimmed && te <= ts && to == 0)) {
                    UIColor *sc = gColoredPass ? [ResolveColor(node[@"stroke"]) colorWithAlphaComponent:a] : [UIColor colorWithWhite:0 alpha:a];
                    CGContextSetStrokeColorWithColor(ctx, sc.CGColor);
                    CGContextSetLineWidth(ctx, sw);
                    NSString *cap = node[@"strokeLineCap"], *join = node[@"strokeLineJoin"];
                    CGContextSetLineCap(ctx, [cap isEqualToString:@"round"] ? kCGLineCapRound : [cap isEqualToString:@"square"] ? kCGLineCapSquare : kCGLineCapButt);
                    CGContextSetLineJoin(ctx, [join isEqualToString:@"round"] ? kCGLineJoinRound : [join isEqualToString:@"bevel"] ? kCGLineJoinBevel : kCGLineJoinMiter);
                    CGContextAddPath(ctx, sp);
                    CGContextStrokePath(ctx);
                }
                CGPathRelease(sp);
            }
            CGPathRelease(base);
        }
    }
}


#pragma mark - AnimatedVectorDrawable playback
// Replays the animators exported by scripts/export_vectors.py ("base" tree +
// "anims" per target name) at time t (ms). Interpolators are the AVD ones:
// cubic pathInterpolator control points, a path interpolator, or the Android
// default (accelerateDecelerate).

static CGFloat CubicBezierY(double x1, double y1, double x2, double y2, double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    double t = x;
    for (int i = 0; i < 8; i++) { // Newton on x(t) = x
        double xt = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t;
        double dx = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2);
        if (fabs(dx) < 1e-6) break;
        t -= (xt - x) / dx;
        t = MAX(0, MIN(1, t));
    }
    return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t;
}

static CGFloat PathInterpolatorY(NSString *d, CGFloat x) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSArray *pts = cache[d];
    if (!pts) {
        CGPathRef p = [LQSVectorIcon newPathFromString:d];
        NSMutableArray *a = [NSMutableArray array], *br = [NSMutableArray array];
        if (p) { AppendFlattened(p, a, br); CGPathRelease(p); }
        pts = a; cache[d] = a;
    }
    for (NSUInteger i = 1; i < pts.count; i++) {
        CGPoint a = [pts[i - 1] CGPointValue], b = [pts[i] CGPointValue];
        if (x <= b.x) return b.x == a.x ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
    }
    return pts.count ? [pts.lastObject CGPointValue].y : x;
}

static CGFloat Ease(NSDictionary *interp, CGFloat f) {
    NSArray *c = interp[@"cubic"];
    if (c.count == 4) return CubicBezierY([c[0] doubleValue], [c[1] doubleValue], [c[2] doubleValue], [c[3] doubleValue], f);
    if ([interp[@"path"] isKindOfClass:NSString.class]) return PathInterpolatorY(interp[@"path"], f);
    NSString *n = interp[@"name"];
    if ([n isEqualToString:@"linear"] || [n isEqualToString:@"linearInterpolator"]) return f;
    return (cos((f + 1) * M_PI) / 2.0) + 0.5; // accelerateDecelerate (Android default)
}

// Numbers of two path strings with identical command structure are lerped
// (Android pathType morph requires compatible paths).
static NSString *MorphPath(NSString *from, NSString *to, CGFloat f) {
    if (f <= 0) return from;
    if (f >= 1) return to;
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"-?\\d*\\.?\\d+(?:[eE]-?\\d+)?" options:0 error:nil];
    NSArray *ma = [re matchesInString:from options:0 range:NSMakeRange(0, from.length)];
    NSArray *mb = [re matchesInString:to options:0 range:NSMakeRange(0, to.length)];
    if (ma.count != mb.count) return f < 0.5 ? from : to;
    NSMutableString *out = [NSMutableString string];
    NSUInteger last = 0;
    for (NSUInteger i = 0; i < ma.count; i++) {
        NSRange ra = [ma[i] range], rb = [mb[i] range];
        [out appendString:[from substringWithRange:NSMakeRange(last, ra.location - last)]];
        double a = [[from substringWithRange:ra] doubleValue], b = [[to substringWithRange:rb] doubleValue];
        [out appendFormat:@" %.4f ", a + (b - a) * f];
        last = NSMaxRange(ra);
    }
    [out appendString:[from substringFromIndex:last]];
    return out;
}

static CGPoint PointOnPath(NSString *d, CGFloat f) {
    CGPathRef p = [LQSVectorIcon newPathFromString:d];
    if (!p) return CGPointZero;
    NSMutableArray *pts = [NSMutableArray array], *br = [NSMutableArray array];
    AppendFlattened(p, pts, br);
    CGPathRelease(p);
    if (pts.count < 2) return pts.count ? [pts[0] CGPointValue] : CGPointZero;
    CGFloat total = 0;
    for (NSUInteger i = 1; i < pts.count; i++) { CGPoint a = [pts[i - 1] CGPointValue], b = [pts[i] CGPointValue]; total += hypot(b.x - a.x, b.y - a.y); }
    CGFloat target = MAX(0, MIN(1, f)) * total, acc = 0;
    for (NSUInteger i = 1; i < pts.count; i++) {
        CGPoint a = [pts[i - 1] CGPointValue], b = [pts[i] CGPointValue];
        CGFloat l = hypot(b.x - a.x, b.y - a.y);
        if (acc + l >= target && l > 0) { CGFloat k = (target - acc) / l; return CGPointMake(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k); }
        acc += l;
    }
    return [pts.lastObject CGPointValue];
}

static NSArray *AnimatedNodes(NSArray *nodes, NSDictionary *anims, CGFloat t) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *node in nodes) {
        NSMutableDictionary *n = [node mutableCopy];
        BOOL isGroup = [n[@"type"] isEqualToString:@"group"];
        NSMutableDictionary *tr = isGroup ? [(n[@"transform"] ?: @{}) mutableCopy] : nil;
        NSArray *list = [n[@"name"] isKindOfClass:NSString.class] ? anims[n[@"name"]] : nil;
        // Apply in start order: a later animator owns the property once it has started.
        NSArray *sorted = [list sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"start"] compare:b[@"start"]]; }];
        NSMutableSet *touched = [NSMutableSet set];
        for (NSDictionary *a in sorted) {
            CGFloat start = [a[@"start"] doubleValue], dur = MAX(1, [a[@"duration"] doubleValue]);
            NSString *prop = a[@"prop"];
            if (t < start && [touched containsObject:prop]) continue;
            CGFloat f = Ease(a[@"interp"], MAX(0, MIN(1, (t - start) / dur)));
            [touched addObject:prop];
            if ([prop isEqualToString:@"translateXY"]) {
                CGPoint pt = PointOnPath(a[@"path"], f);
                tr[@"translateX"] = @(pt.x); tr[@"translateY"] = @(pt.y);
                continue;
            }
            if ([prop isEqualToString:@"pathData"]) {
                NSString *from = a[@"from"] ?: n[@"d"], *to = a[@"to"] ?: n[@"d"];
                if ([from isKindOfClass:NSString.class] && [to isKindOfClass:NSString.class]) n[@"d"] = MorphPath(from, to, f);
                continue;
            }
            NSArray *kfs = a[@"keyframes"];
            CGFloat value;
            if (kfs.count) {
                value = [kfs.lastObject[@"v"] doubleValue];
                for (NSUInteger k = 1; k < kfs.count; k++) {
                    CGFloat f0 = [kfs[k - 1][@"f"] doubleValue], f1 = [kfs[k][@"f"] doubleValue];
                    if (f <= f1) { CGFloat kk = f1 > f0 ? (f - f0) / (f1 - f0) : 1; value = [kfs[k - 1][@"v"] doubleValue] + ([kfs[k][@"v"] doubleValue] - [kfs[k - 1][@"v"] doubleValue]) * kk; break; }
                }
            } else {
                NSDictionary *cur = isGroup ? tr : n;
                CGFloat def = [prop hasPrefix:@"scale"] || [prop hasSuffix:@"Alpha"] || [prop isEqualToString:@"trimPathEnd"] ? 1 : 0;
                CGFloat from = [a[@"from"] isKindOfClass:NSNumber.class] ? [a[@"from"] doubleValue] : Num(cur, prop, def);
                CGFloat to = [a[@"to"] isKindOfClass:NSNumber.class] ? [a[@"to"] doubleValue] : Num(cur, prop, def);
                value = from + (to - from) * f;
            }
            if (isGroup) tr[prop] = @(value); else n[prop] = @(value);
        }
        if (isGroup) {
            n[@"transform"] = tr;
            n[@"children"] = AnimatedNodes(node[@"children"], anims, t);
        }
        [out addObject:n];
    }
    return out;
}

static NSDictionary *LoadJSON(NSString *name) {
    static NSCache *jsonCache;
    if (!jsonCache) jsonCache = [NSCache new];
    NSDictionary *j = [jsonCache objectForKey:name];
    if (j) return j;
    NSData *data = [NSData dataWithContentsOfFile:[gResourceDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]]];
    j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([j isKindOfClass:NSDictionary.class]) [jsonCache setObject:j forKey:name];
    return j;
}

@implementation LQSVectorIcon

+ (void)setResourceDirectory:(NSString *)path {
    gResourceDirectory = [path copy];
    [gImageCache removeAllObjects];
}

+ (NSString *)resourceDirectory {
    return gResourceDirectory;
}

+ (NSTimeInterval)animationDurationNamed:(NSString *)name {
    NSDictionary *j = gResourceDirectory ? LoadJSON(name) : nil;
    return j[@"anims"] ? [j[@"animDuration"] doubleValue] / 1000.0 : 0;
}

+ (UIImage *)frameNamed:(NSString *)name side:(CGFloat)side atTime:(NSTimeInterval)seconds {
    NSDictionary *json = gResourceDirectory ? LoadJSON(name) : nil;
    if (!json[@"anims"] || !json[@"base"]) return [self imageNamed:name side:side];
    NSArray *viewport = json[@"viewport"];
    CGFloat vw = [viewport.firstObject doubleValue] ?: 24, vh = [viewport.lastObject doubleValue] ?: 24;
    NSArray *nodes = AnimatedNodes(json[@"base"], json[@"anims"], seconds * 1000.0);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:[UIGraphicsImageRendererFormat preferredFormat]];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGFloat scale = MIN(side / vw, side / vh);
        CGContextTranslateCTM(ctx, (side - vw * scale) / 2, (side - vh * scale) / 2);
        CGContextScaleCTM(ctx, scale, scale);
        CGContextSetAlpha(ctx, Num(json, @"alpha", 1));
        DrawNodes(ctx, nodes);
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (CGPathRef)newPathFromString:(NSString *)d {
    if (![d isKindOfClass:NSString.class] || d.length == 0 || [d hasPrefix:@"@"]) return NULL;
    const char *c = d.UTF8String;
    return NewPathFromCString(c, strlen(c));
}

+ (void)setColorResolver:(UIColor * (^)(NSString *))resolver { gColorResolver = [resolver copy]; }

+ (UIImage *)coloredImageNamed:(NSString *)name side:(CGFloat)side {
    gColoredPass = YES;
    UIImage *img = [self imageNamed:name side:side colored:YES];
    gColoredPass = NO;
    return img;
}

+ (UIImage *)imageNamed:(NSString *)name side:(CGFloat)side {
    return [self imageNamed:name side:side colored:NO];
}

+ (UIImage *)imageNamed:(NSString *)name height:(CGFloat)height {
    if (!name.length || !gResourceDirectory) return nil;
    NSString *key = [NSString stringWithFormat:@"%@#h%.1f", name, height];
    UIImage *cached = [gImageCache objectForKey:key];
    if (cached) return cached;
    NSData *data = [NSData dataWithContentsOfFile:[gResourceDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]]];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSArray *vp = json[@"viewport"];
    CGFloat vw = [vp.firstObject doubleValue] ?: 24, vh = [vp.lastObject doubleValue] ?: 24;
    CGSize size = CGSizeMake(height * vw / vh, height); // exact width: ceil() added ~1pt of empty space
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:[UIGraphicsImageRendererFormat preferredFormat]];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGContextScaleCTM(ctx, height / vh, height / vh);
        CGContextSetAlpha(ctx, Num(json, @"alpha", 1));
        DrawNodes(ctx, json[@"nodes"]);
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!gImageCache) gImageCache = [NSCache new];
    [gImageCache setObject:img forKey:key];
    return img;
}

+ (UIImage *)imageNamed:(NSString *)name side:(CGFloat)side colored:(BOOL)colored {
    if (!name.length || !gResourceDirectory) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gImageCache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@@%.1f%@", name, side, colored ? @"c" : @""];
    UIImage *cached = [gImageCache objectForKey:key];
    if (cached) return cached;

    NSString *file = [gResourceDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
    NSData *data = [NSData dataWithContentsOfFile:file];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSArray *viewport = json[@"viewport"];
    CGFloat vw = [viewport.firstObject doubleValue] ?: 24, vh = [viewport.lastObject doubleValue] ?: 24;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGFloat scale = MIN(side / vw, side / vh);
        CGContextTranslateCTM(ctx, (side - vw * scale) / 2, (side - vh * scale) / 2);
        CGContextScaleCTM(ctx, scale, scale);
        CGContextSetAlpha(ctx, Num(json, @"alpha", 1));
        DrawNodes(ctx, json[@"nodes"]);
    }];
    img = [img imageWithRenderingMode:colored ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate];
    [gImageCache setObject:img forKey:key];
    return img;
}

@end
