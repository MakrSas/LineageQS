// Android "Internet" and Bluetooth "Connect" dialogs (tap on the Wi-Fi / Bluetooth
// tile body; docs/qs-detail-panels.md): internet_connectivity_dialog.xml and
// bluetooth_tile_dialog.xml rebuilt in UIKit, data from LQSBackends.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LQSDetailKind) {
    LQSDetailKindInternet,
    LQSDetailKindBluetooth,
};

@interface LQSDetailDialog : UIView
@property (nonatomic, readonly) LQSDetailKind kind;
// Asks the owner to close the shade and open an iOS Settings page for `tile`.
@property (nonatomic, copy, nullable) void (^openSettings)(NSString *tile);
// Called after a toggle so the owner can refresh the tile.
@property (nonatomic, copy, nullable) void (^stateChanged)(void);
- (instancetype)initWithKind:(LQSDetailKind)kind;
- (void)presentInView:(UIView *)host;
- (void)dismiss;
- (void)reload; // live updates while open
@end

NS_ASSUME_NONNULL_END
