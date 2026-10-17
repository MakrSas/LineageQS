// Media controls card under QQS (Android 17 media carousel, single player).
// Layout values are an approximation of the Compose media card (assumption):
// 28dp corners (qs_corner_radius), artwork background with a dark scrim,
// title / artist, 48dp transport buttons, primary play button.
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface LQSMediaCard : UIView
@property (nonatomic, readonly) BOOL hasMedia;
@property (nonatomic, copy, nullable) void (^onChange)(void);
+ (CGFloat)height;
@end
NS_ASSUME_NONNULL_END
