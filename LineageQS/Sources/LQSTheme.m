#import "LQSTheme.h"
#import "LQSVectorIcon.h"
#import <CoreText/CoreText.h>

static NSString *gRoot;
static NSDictionary<NSString *, NSString *> *gColors; // colors.json: name -> #RRGGBB

static UIColor *Hex(NSString *hex, CGFloat alpha) {
    unsigned v = 0;
    [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
    if (hex.length == 9) { alpha *= ((v >> 24) & 0xff) / 255.0; }
    return [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0 green:((v >> 8) & 0xff) / 255.0 blue:(v & 0xff) / 255.0 alpha:alpha];
}

// Defaults (framework-res, no seed) overlaid by the user's Material You theme
// (<state>/theme.json, written by the Colors settings screen; same key names).
#import <dlfcn.h>
// roothide / Nyxian jailed: processes may not share /var/mobile, so the theme is
// mirrored under the jailbreak root, which every process sees.
static NSString *MYJBThemePath(void) {
    const char *(*jbroot)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    const char *r = jbroot ? jbroot("/var/mobile/Library/MaterialYou/theme.json") : NULL;
    return r ? @(r) : nil;
}

static NSString *gThemePath = @"/var/mobile/Library/MaterialYou/theme.json"; // com.makr.materialyou

static NSDictionary *Colors(void) {
    if (!gColors && gRoot) {
        NSData *d = [NSData dataWithContentsOfFile:[gRoot stringByAppendingPathComponent:@"colors.json"]];
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:(d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil) ?: @{}];
        NSString *tp = gThemePath, *jb = MYJBThemePath();
        NSDate *(^mtime)(NSString *) = ^NSDate *(NSString *f) { return [[NSFileManager defaultManager] attributesOfItemAtPath:f error:nil].fileModificationDate; };
        if (jb && mtime(jb) && (!mtime(tp) || [mtime(jb) compare:mtime(tp)] == NSOrderedDescending)) tp = jb;
        NSData *t = [NSData dataWithContentsOfFile:tp] ?: [NSData dataWithContentsOfFile:@"/var/mobile/Library/LineageQS/theme.json"]; // pre-1.0 location
        NSDictionary *theme = t ? [NSJSONSerialization JSONObjectWithData:t options:0 error:nil] : nil;
        if ([theme[@"colors"] isKindOfClass:NSDictionary.class]) [m addEntriesFromDictionary:theme[@"colors"]];
        gColors = m;
    }
    return gColors ?: @{};
}

static BOOL IsDark(UITraitCollection *t) { return t.userInterfaceStyle != UIUserInterfaceStyleLight; }

// Light/dark pair from framework-res colors.xml (system_<name>_light / _dark).
static UIColor *Pair(NSString *name, CGFloat alpha) {
    NSString *light = Colors()[[name stringByAppendingString:@"_light"]] ?: @"#808080";
    NSString *dark = Colors()[[name stringByAppendingString:@"_dark"]] ?: @"#808080";
    UIColor *l = Hex(light, alpha), *d = Hex(dark, alpha);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) { return IsDark(t) ? d : l; }];
}

UIColor *LQSColor(NSString *role) { return Pair([@"system_" stringByAppendingString:role], 1); }

// colors_dynamic.xml: system_<pal>_<step> -> _light, values-night -> _dark.
UIColor *LQSPalette(NSString *palette, NSInteger step) {
    return Pair([NSString stringWithFormat:@"system_%@_%ld", palette, (long)step], 1);
}
UIColor *LQSNeutral1(NSInteger step) { return LQSPalette(@"neutral1", step); }
UIColor *LQSNeutral2(NSInteger step) { return LQSPalette(@"neutral2", step); }

// ColorUtils.compositeColors(fg, bg) (premultiplied "over").
static void Over(CGFloat fg[4], const CGFloat bg[4], CGFloat out[4]) {
    CGFloat a = fg[3] + bg[3] * (1 - fg[3]);
    for (int i = 0; i < 3; i++) out[i] = a > 0 ? (fg[i] * fg[3] + bg[i] * bg[3] * (1 - fg[3])) / a : 0;
    out[3] = a;
}
static void Comp(UIColor *c, CGFloat alpha, CGFloat out[4]) {
    [c getRed:&out[0] green:&out[1] blue:&out[2] alpha:&out[3]];
    out[3] *= alpha;
}

static NSMutableDictionary<NSString *, NSString *> *gFontNames;

static NSString *RegisteredFont(NSString *file) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gFontNames = [NSMutableDictionary dictionary]; });
    @synchronized (gFontNames) {
        if (gFontNames[file]) return gFontNames[file];
        NSURL *url = [NSURL fileURLWithPath:[[gRoot stringByAppendingPathComponent:@"fonts"] stringByAppendingPathComponent:file]];
        NSArray *descs = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
        NSString *name = nil;
        if (descs.count) {
            name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)descs.firstObject, kCTFontNameAttribute));
            CFErrorRef err = NULL;
            if (!CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &err) && err) CFRelease(err);
        }
        gFontNames[file] = name ?: @"";
        return gFontNames[file];
    }
}

@implementation LQSTheme

+ (void)setResourceRoot:(NSString *)root {
    gRoot = [root copy];
    gColors = nil;
    // Vector colours such as "?attr/colorPrimary" / "@android:color/system_neutral1_700".
    [LQSVectorIcon setColorResolver:^UIColor *(NSString *ref) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"system_(neutral[12]|accent[123])_(\\d+)" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:ref options:0 range:NSMakeRange(0, ref.length)];
        if (!m) return nil;
        return LQSPalette([ref substringWithRange:[m rangeAtIndex:1]], [[ref substringWithRange:[m rangeAtIndex:2]] integerValue]);
    }];
}
+ (NSString *)resourceRoot { return gRoot; }
+ (void)reloadTheme { gColors = nil; }
+ (void)setThemePath:(NSString *)path { gThemePath = [path copy]; gColors = nil; }

+ (CGFloat)dp:(CGFloat)dp { return dp; }

// Google Sans Flex (OFL, google/fonts) — the Pixel / Android 16-17 system font behind
// the "variable-*" families; Roboto Flex as fallback. Axes set through CoreText
// (UIFont descriptors drop kCTFontVariationAttribute): wght, opsz = point size.
+ (UIFont *)sansWithSize:(CGFloat)pt weight:(CGFloat)wght {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%.1f/%.0f", pt, wght];
    if (cache[key]) return cache[key];
    NSString *name = RegisteredFont(@"GoogleSansFlex.ttf");
    if (!name.length) name = RegisteredFont(@"RobotoFlex-Regular.ttf");
    UIFont *out = nil;
    if (name.length) {
        NSDictionary *axes = @{@(0x77676874): @(wght), @(0x6F70737A): @(MAX(6, MIN(144, pt)))}; // 'wght', 'opsz'
        CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)@{(__bridge NSString *)kCTFontNameAttribute: name,
                                                                                               (__bridge NSString *)kCTFontVariationAttribute: axes});
        CTFontRef f = CTFontCreateWithFontDescriptor(d, pt, NULL);
        CFRelease(d);
        out = (__bridge_transfer UIFont *)f;
    }
    if (!out) out = [UIFont systemFontOfSize:pt weight:wght >= 600 ? UIFontWeightSemibold : wght >= 500 ? UIFontWeightMedium : UIFontWeightRegular];
    cache[key] = out;
    return out;
}
// TypographyTokens.kt:213-220 (titleSmallEmphasized), :106-113 (labelMedium);
// bodyMediumEmphasized: TypeScaleTokens.kt:28-29 (weight: Medium, assumption for "emphasized").
+ (UIFont *)tileLabelFont { return [self sansWithSize:14 weight:600]; }
+ (UIFont *)tileSecondaryFont { return [self sansWithSize:12 weight:500]; }
+ (UIFont *)headerFont { return [self sansWithSize:14 weight:500]; }

+ (UIColor *)primary { return LQSColor(@"primary"); }
+ (UIColor *)onPrimary { return LQSColor(@"on_primary"); }
+ (UIColor *)onSurface { return LQSColor(@"on_surface"); }
+ (UIColor *)onSurfaceVariant { return LQSColor(@"on_surface_variant"); }
+ (UIColor *)surface { return LQSColor(@"surface"); }
+ (UIColor *)secondary { return LQSColor(@"secondary"); }
// customColorSurfaceEffect1/2 -> system_surface_effect_1/2; monet opacity 0.54
// (effect1) and 0.32 light / 0.15 dark (effect2) from CustomDynamicColors.java:354-371
// (assumption: the runtime colour carries that alpha; static res has none).
+ (UIColor *)surfaceEffect1 { return Pair(@"system_surface_effect_1", 0.54); }
+ (UIColor *)surfaceEffect2 {
    UIColor *l = Pair(@"system_surface_effect_2", 0.32), *d = Pair(@"system_surface_effect_2", 0.15);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) { return [IsDark(t) ? d : l resolvedColorWithTraitCollection:t]; }];
}

// shade_panel_fg (accent1_100 light / accent1_800 dark, alpha 0.32) over
// shade_panel_bg (neutral1_500 with lStar 98 / 4, alpha 0.32), over
// shade_panel_scrim (#404040 alpha 0.40): ShadeColors.kt:33-43, 89-95.
// lStar re-toning of neutral1_500 is approximated as #F8F8FB / #0E0E10 (assumption).
+ (UIColor *)shadePanel {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        BOOL dark = IsDark(t);
        CGFloat fg[4], bg[4], scrim[4], a[4], out[4];
        Comp([LQSPalette(@"accent1", dark ? 800 : 100) resolvedColorWithTraitCollection:t], 0.32, fg);
        Comp(Hex(dark ? @"#0E0E10" : @"#F8F8FB", 1), 0.32, bg);
        Comp(Hex(@"#404040", 1), 0.40, scrim);
        Over(fg, bg, a);
        Over(a, scrim, out);
        return [UIColor colorWithRed:out[0] green:out[1] blue:out[2] alpha:out[3]];
    }];
}
+ (UIColor *)notificationScrim {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return [[LQSPalette(@"accent1", IsDark(t) ? 800 : 100) resolvedColorWithTraitCollection:t] colorWithAlphaComponent:0.5]; // ShadeColors.kt:103-108
    }];
}
+ (UIColor *)headerText {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) { return IsDark(t) ? UIColor.whiteColor : UIColor.blackColor; }];
}

+ (CGFloat)tileHeight { return 72; }       // shade_dimens.xml:39
+ (CGFloat)tileGap { return 8; }           // dimens.xml:706-707
+ (CGFloat)sideInset { return 16; }        // qs_horizontal_margin, dimens.xml:719
+ (CGFloat)radiusActive { return 24; }     // shade_dimens.xml:31
+ (CGFloat)radiusInactive { return 36; }   // 50 dp, clamped to half of 72 (Compose RoundedCornerShape)
+ (CGFloat)iconRadiusActive { return 16; } // shade_dimens.xml:32
+ (CGFloat)iconSide { return 32; }         // shade_dimens.xml:34
+ (CGFloat)largeIconSide { return 28; }    // shade_dimens.xml:37
+ (CGFloat)toggleTarget { return 56; }     // shade_dimens.xml:40

@end
