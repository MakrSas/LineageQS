// SystemUI-level Material You glue over the libmonet port (LineageQS/Monet):
// com.android.systemui.monet.ColorScheme / DynamicColors (seed colors -> the
// system_* colour table) and android.app.WallpaperColors.fromBitmap +
// ColorScheme.getSeedColors (wallpaper -> up to 4 seeds).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ThemeStyle names used in settings: "neutral" (SPRITZ), "tonal_spot", "vibrant", "expressive".
@interface LQSMonet : NSObject
// {"system_<token>_light": "#RRGGBB", "system_<token>_dark": ...} for every
// DynamicColors token (dynamic, fixed, custom) and palette shade (accent1..3,
// neutral1..2, error) — the same keys as Resources/colors.json. SPEC_2026, PHONE.
+ (NSDictionary<NSString *, NSString *> *)systemColorsForSeeds:(NSArray<NSNumber *> *)seeds style:(NSString *)style;
// One theme (light or dark): token -> ARGB.
+ (NSDictionary<NSString *, NSNumber *> *)schemeForSeeds:(NSArray<NSNumber *> *)seeds style:(NSString *)style dark:(BOOL)dark;
// WallpaperColors.fromBitmap (112x112 area, Celebi 128) + getSeedColors(filter = YES), max 4.
+ (NSArray<NSNumber *> *)seedColorsFromImage:(UIImage *)image;
// ColorProviderUtil: freeform seed = Hct.from(hue, 100, 80).
+ (int)freeformSeedForHue:(double)hue;
+ (double)hueOfColor:(int)argb;
// Swatch colour of a seed option: accent1 tone 45 (s450) light / s200 dark (ColorProviderUtil.kt:296-311).
+ (int)swatchColorForSeed:(int)seed style:(NSString *)style dark:(BOOL)dark;
@end

NS_ASSUME_NONNULL_END
