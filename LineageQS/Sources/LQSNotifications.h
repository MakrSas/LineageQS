// Mirror of the notifications SpringBoard currently holds, fed by hooks on
// NCNotificationDispatcher (post / modify / withdraw) in Tweak.xm. UI-facing
// model for the Android notification shade; actions go back through the
// dispatcher so iOS stays the source of truth (Notification Center stays in sync).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const LQSNotificationsChangedNotification;

@interface LQSNotificationItem : NSObject
@property (nonatomic, strong, readonly) id request;        // NCNotificationRequest
@property (nonatomic, copy, readonly) NSString *identifier; // notificationIdentifier
@property (nonatomic, copy, readonly) NSString *bundleID;   // sectionIdentifier
@property (nonatomic, copy, readonly, nullable) NSString *threadID;
@property (nonatomic, copy, readonly, nullable) NSString *appName, *title, *subtitle, *message;
@property (nonatomic, strong, readonly, nullable) NSDate *date;
@property (nonatomic, strong, readonly, nullable) UIImage *icon, *attachment;
@end

@interface LQSNotifications : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<LQSNotificationItem *> *items; // newest first
@property (nonatomic, weak, nullable) id dispatcher;                   // NCNotificationDispatcher
- (void)posted:(id)request;
- (void)modified:(id)request;
- (void)withdrawn:(id)request;
// Actions (through the dispatcher): open runs the default action, clear removes it everywhere.
- (BOOL)openItem:(LQSNotificationItem *)item;
- (BOOL)clearItems:(NSArray<LQSNotificationItem *> *)items;
- (NSString *)debugListing;
@end

NS_ASSUME_NONNULL_END
