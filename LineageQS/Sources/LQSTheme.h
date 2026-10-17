// Visual tokens of the Android 17 (LineageOS 24.0) shade / Quick Settings,
// converted to iOS points (1 dp = 1 pt; iPhone 8 is 375 pt wide, close to a
// 360-411 dp Android phone). Sources: docs/qs-tiles-tokens.md,
// docs/qs-shade-layout.md, docs/shade-motion.md; every value notes its origin.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Material You colour role from framework-res (system_<role>_light/_dark,
// Resources/colors.json). Dynamic: follows the light/dark trait. Default
// (no wallpaper seed) palette; monet from the iOS wallpaper is not done yet.
FOUNDATION_EXTERN UIColor *LQSColor(NSString *role);
// Tonal palette entry, e.g. LQSPalette(@"accent1", 800).
FOUNDATION_EXTERN UIColor *LQSPalette(NSString *palette, NSInteger step);
// Compatibility with code kept from an earlier prototype (dialogs): neutral1/neutral2 tones.
FOUNDATION_EXTERN UIColor *LQSNeutral1(NSInteger step);
FOUNDATION_EXTERN UIColor *LQSNeutral2(NSInteger step);

@interface LQSTheme : NSObject
// Directory with fonts/, vectors/, strings/ and colors.json.
+ (void)setResourceRoot:(NSString *)root;
+ (NSString *)resourceRoot;
// Re-read <state>/theme.json (Material You colours chosen in Settings). Colours
// already handed out keep their values: rebuild views after calling this.
+ (void)reloadTheme;
+ (void)setThemePath:(NSString *)path; // preview host / Settings preview

+ (CGFloat)dp:(CGFloat)dp; // 1:1

// Roboto Flex (variable wght). AOSP "variable-*" font families resolve to the
// device sans-serif; Google Sans Flex is Pixel-only and not used.
+ (UIFont *)sansWithSize:(CGFloat)pt weight:(CGFloat)wght;
// Text styles (Material 3 type scale used by SystemUI).
+ (UIFont *)tileLabelFont;      // titleSmallEmphasized 14/20 SemiBold
+ (UIFont *)tileSecondaryFont;  // labelMedium 12/16 Medium, tracking 0.1
+ (UIFont *)headerFont;         // bodyMediumEmphasized 14/20

// Roles used by the QS tiles (Tile.kt:529-584).
+ (UIColor *)primary;
+ (UIColor *)onPrimary;
+ (UIColor *)onSurface;
+ (UIColor *)onSurfaceVariant;
+ (UIColor *)surface;
+ (UIColor *)surfaceEffect1;   // inactive tile / slider track
+ (UIColor *)surfaceEffect2;   // inactive dual-target icon bubble
+ (UIColor *)secondary;
// Shade panel colour over the blur (ShadeColors.shadePanel(withScrim = true)).
+ (UIColor *)shadePanel;
+ (UIColor *)notificationScrim; // notification_scrim_base @ 0.5
+ (UIColor *)headerText;        // shade_header_text_color

// Geometry.
+ (CGFloat)tileHeight;          // 72
+ (CGFloat)tileGap;             // 8 (horizontal and vertical)
+ (CGFloat)sideInset;           // 16
+ (CGFloat)radiusActive;        // 24
+ (CGFloat)radiusInactive;      // 36 (50 dp clamped to half height)
+ (CGFloat)iconRadiusActive;    // 16
+ (CGFloat)iconSide;            // 32 (icon-only tile)
+ (CGFloat)largeIconSide;       // 28
+ (CGFloat)toggleTarget;        // 56
@end

NS_ASSUME_NONNULL_END
