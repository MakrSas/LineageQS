// Now playing via MediaRemote (SpringBoard). Read + transport commands only.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const LQSMediaChangedNotification;

@interface LQSMedia : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL hasMedia, playing;
@property (nonatomic, copy, readonly, nullable) NSString *title, *artist, *appName, *bundleID;
@property (nonatomic, strong, readonly, nullable) UIImage *artwork;
@property (nonatomic, readonly) NSTimeInterval duration, elapsed; // elapsed extrapolated with playbackRate
- (void)start;   // register for MediaRemote notifications, fetch now
- (void)refresh;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekTo:(NSTimeInterval)t;
@end

NS_ASSUME_NONNULL_END
