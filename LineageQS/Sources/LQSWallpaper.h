#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LQSWallpaper : NSObject
+ (nullable UIImage *)currentImage; // home screen wallpaper, lock screen as fallback
@end

NS_ASSUME_NONNULL_END
