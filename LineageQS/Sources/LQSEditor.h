// Android 17 Quick Settings edit mode (qs/panels/ui/compose/infinitegrid/EditTile.kt,
// selection/*, DragAndDropState.kt; docs/qs-edit-mode.md). Changes are applied
// immediately, like Android (every action persists the layout through LQSModel).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LQSEditor : UIView
@property (nonatomic, copy, nullable) void (^onExit)(void);
@property (nonatomic) CGFloat topInset; // qqsHeaderHeight
- (void)reload;
@end

NS_ASSUME_NONNULL_END
