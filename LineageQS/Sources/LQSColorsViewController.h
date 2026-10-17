// Android 17 "Colors" picker (ThemePicker picker/color/ui/compose/*, docs/colors-picker.md):
// live shade preview, wallpaper colour swatches, freeform hue slider ("Select a
// color"), theme style variants (Neutral / Soft / Bright / Bold), dark theme switch.
// Apply writes the system_* colour table to <state>/theme.json and posts
// com.makr.lineageqs/theme-changed.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const LQSThemeChangedNotification; // Darwin

@interface LQSColorsViewController : UIViewController
@property (nonatomic, copy) NSString *themePath;          // default /var/mobile/Library/LineageQS/theme.json
@property (nonatomic, strong, nullable) UIImage *wallpaper; // default: LQSWallpaper currentImage
@end

NS_ASSUME_NONNULL_END
