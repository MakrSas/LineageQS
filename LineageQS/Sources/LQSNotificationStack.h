// Notification list of the Android 17 single shade (under QQS): app groups as
// rounded rows (notification_corner_radius 28dp, 4dp between rows of a group,
// 2dp dividers), footer with "Manage" and "Clear all". Data: LQSNotifications.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LQSNotificationStack : UIView
@property (nonatomic, copy, nullable) void (^requestDismiss)(void);
@property (nonatomic, copy, nullable) void (^openSettingsURL)(NSString *url);
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic) BOOL showsBackground; // NO when the panel draws a full-height surface
- (void)reload;
- (CGFloat)contentHeight;
@end

NS_ASSUME_NONNULL_END
