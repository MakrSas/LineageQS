// Visual building blocks of the Android 17 shade. Purely presentational:
// taps are reported to the owner, which talks to LQSBackends.
#import <UIKit/UIKit.h>
#import "LQSModel.h"

NS_ASSUME_NONNULL_BEGIN

// Compose Tile (qs/panels/ui/compose/infinitegrid/Tile.kt, CommonTile.kt).
@interface LQSTileView : UIControl
@property (nonatomic, strong, readonly) LQSTileSpec *spec;
@property (nonatomic) LQSTileSize size;
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated; // colours/shape spring + AnimatedVectorDrawable
@property (nonatomic) BOOL unavailable;
@property (nonatomic, copy, nullable) NSString *stateText;   // secondary label
@property (nonatomic, copy, nullable) NSString *iconOverride; // live icon (Wi-Fi bars, cellular bars)
@property (nonatomic, readonly) BOOL lastTouchInIcon;         // large dual-target: icon bubble = toggle
@property (nonatomic) CGFloat squish;                          // 0.1...1 vertical squish (SquishTile.kt)
// Container bounce (BounceableTileViewModel / BounceableInfo): extra width while
// pressed; the owner shrinks the neighbour. Set by the panel.
@property (nonatomic, copy, nullable) void (^onPress)(LQSTileView *tile, BOOL pressed);
- (instancetype)initWithSpec:(LQSTileSpec *)spec size:(LQSTileSize)size;
- (void)contentBounce; // icon x1.10 / label x1.06, 334 ms (BounceableTileViewModel.kt:63-78)
@property (nonatomic, readonly) BOOL bouncesContainer; // isToggleable && (iconOnly || !dualTarget)
@end

// Material 3 expressive slider (brightness/ui/compose/BrightnessSlider.kt).
@interface LQSBrightnessView : UIControl
@property (nonatomic) CGFloat value; // 0...1
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic) BOOL showAuto;
@property (nonatomic) BOOL autoOn;
@property (nonatomic, copy, nullable) void (^onAutoToggle)(BOOL on);
@property (nonatomic, copy, nullable) void (^onDragChanged)(BOOL dragging); // brightness mirror
@end

// Unified battery (statusbar/pipeline/battery/ui/composable/UnifiedBattery.kt).
@interface LQSBatteryView : UIView
@property (nonatomic) NSInteger level;  // 0...100
@property (nonatomic) BOOL charging;
@property (nonatomic) BOOL powerSave;
@property (nonatomic) BOOL showPercent; // percent glyphs inside the body
@property (nonatomic) BOOL darkBackground; // DarkTheme colours (white) vs LightTheme
@end

// Shade header: collapsed (clock + date | status chip) and expanded (big clock,
// carrier | date, chip) states, morphed by expansion 0...1 (QQS -> QS).
@interface LQSHeaderView : UIView
@property (nonatomic) CGFloat expansion;
- (void)applyLiveInfo:(NSDictionary *)info;
- (void)refresh;
@property (nonatomic, readonly) CGFloat collapsedHeight;
@property (nonatomic, readonly) CGFloat expandedHeight;
@property (nonatomic, copy, nullable) void (^onClockTap)(void);
@property (nonatomic, copy, nullable) void (^onDateTap)(void);
@end

// Footer action button (FooterActions.kt): 40dp circle, 20dp icon.
@interface LQSIconButton : UIControl
- (instancetype)initWithIcon:(NSString *)icon side:(CGFloat)side;
@property (nonatomic, strong) UIColor *fill;
@property (nonatomic, strong) UIColor *glyph;
@end

// Pager dots of the paginated grid footer.
@interface LQSPageDots : UIView
@property (nonatomic) NSInteger pages;
@property (nonatomic) CGFloat position; // fractional page
@end

FOUNDATION_EXTERN void LQSHapticTick(void);
FOUNDATION_EXTERN CGFloat LQSCubic(double x1, double y1, double x2, double y2, double x);

NS_ASSUME_NONNULL_END
