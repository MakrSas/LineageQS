// Root view controller of the Android 17 single shade: header, Quick Quick
// Settings (2 rows) with the notification list below; dragging down expands to
// full Quick Settings (brightness, paged 4x4 grid, footer). In SpringBoard it is
// a child of the native CCUIModularControlCenterOverlayViewController; in the
// preview host it is the window's root. It never presents or dismisses itself:
// it asks its delegate (the native Control Center path) to do that.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LQSPanelViewController;

// Posted (NSNotificationCenter) when a system source says network/status data changed.
FOUNDATION_EXTERN NSString *const LQSLiveInfoChangedNotification;

@protocol LQSPanelDelegate <NSObject>
- (void)panelRequestsDismiss:(LQSPanelViewController *)panel;
@end

typedef NS_ENUM(NSInteger, LQSPanelState) {
    LQSPanelStateCompact,  // QQS + notifications
    LQSPanelStateExpanded, // full QS
    LQSPanelStateEditor,   // edit mode (not implemented yet: behaves as expanded)
};

@interface LQSPanelViewController : UIViewController
@property (nonatomic, weak, nullable) id<LQSPanelDelegate> delegate;
@property (nonatomic, readonly) LQSPanelState state;
- (void)setState:(LQSPanelState)state animated:(BOOL)animated;
// Native presentation progress (CCUIOverlayTransitionState.presentationProgress).
- (void)setPresentationProgress:(CGFloat)progress;
- (void)setPresentationProgress:(CGFloat)progress interactive:(BOOL)interactive;
- (void)reloadFromPreferences;
// Opens the Internet ("wifi"/"internet") or Bluetooth ("bt") dialog.
- (void)showDetailsFor:(NSString *)identifier;
// Kept for Tweak.xm compatibility (NOS dual shade); the Android 17 single shade
// always shows notifications under QQS, so this only selects compact state.
@property (nonatomic) BOOL notificationsMode;
// Preview host: draw our own blurred backdrop (SpringBoard uses the native CC one).
@property (nonatomic) BOOL ownBackdrop;
@end

NS_ASSUME_NONNULL_END
