// Renders Android VectorDrawable data exported by scripts/export_vectors.py.
// Icons come from Android SystemUI (Metroid C5.0) res/drawable; every
// colour is treated like Android's SRC_IN icon tint: geometry and alpha are
// kept, colour comes from the UIImageView tintColor (template image).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LQSVectorIcon : NSObject
// Directory containing <name>.json files. Must be set before first use.
+ (void)setResourceDirectory:(NSString *)path;
+ (nullable NSString *)resourceDirectory;
// Template image rendered at `side` points (square), cached.
+ (nullable UIImage *)imageNamed:(NSString *)name side:(CGFloat)side;
// Multi-colour icons (e.g. ic_qs_edit_resize_*): keeps each path's colour.
// Theme references ("@android:color/system_neutral2_700") go through the resolver.
+ (nullable UIImage *)coloredImageNamed:(NSString *)name side:(CGFloat)side;
// Template image of the given height; width follows the vector viewport ratio
// (status-bar glyphs such as nt_ic_lte_mobiledata are wider than tall).
+ (nullable UIImage *)imageNamed:(NSString *)name height:(CGFloat)height;
+ (void)setColorResolver:(UIColor * _Nullable (^)(NSString *ref))resolver;
// AnimatedVectorDrawable playback (state-change animation of QS icons).
// Duration 0 = the vector has no animation.
+ (NSTimeInterval)animationDurationNamed:(NSString *)name;
+ (nullable UIImage *)frameNamed:(NSString *)name side:(CGFloat)side atTime:(NSTimeInterval)seconds;
// Parses Android/SVG path syntax; exposed for tests.
+ (nullable CGPathRef)newPathFromString:(NSString *)d CF_RETURNS_RETAINED;
@end

NS_ASSUME_NONNULL_END
