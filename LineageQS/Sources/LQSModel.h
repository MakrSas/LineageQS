// Tile catalog, layout and settings of the Android 17 Quick Settings panel.
// Tile identifiers are Android QS tile specs (config.xml quick_settings_tiles_*).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LQSPrefsDomain;            // com.makr.lineageqs
extern NSString *const LQSPrefsChangedNotification; // Darwin: settings changed
extern NSString *const LQSLayoutResetNotification;  // Darwin: reset layout requested
extern NSString *const LQSStateDirectory;           // /var/mobile/Library/LineageQS
extern NSString *const LQSKillSwitchPath;           // <state>/DISABLE

// Android 17 grid tiles have two widths (TileRow.kt:23-24, LargeTileSpanRepository.kt:61):
typedef NS_ENUM(NSInteger, LQSTileSize) {
    LQSTileSizeSmall = 0, // 1 column, icon only
    LQSTileSizeLarge = 1, // 2 columns, icon + label + secondary label
};
FOUNDATION_EXTERN NSInteger LQSTileSpan(LQSTileSize size);
// TileCategory of a spec (qs/tiles/impl/*/...Module.kt): connectivity, utilities,
// display, privacy, accessibility. Order of the enum = order of edit-mode groups.
FOUNDATION_EXTERN NSString *LQSTileCategory(NSString *identifier);
FOUNDATION_EXTERN NSArray<NSString *> *LQSTileCategories(void);
extern const NSUInteger LQSMinimumTiles; // quick_settings_min_num_tiles = 6

@interface LQSTileSpec : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *iconOn;   // vector names (Resources/vectors)
@property (nonatomic, copy, readonly) NSString *iconOff;
@property (nonatomic, readonly) BOOL dualTarget;          // handlesSecondaryClick: BluetoothTile, ModesTile
@property (nonatomic, readonly) BOOL toggleable;          // isToggleable (accessibility role Switch)
@end

@interface LQSTileEntry : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) LQSTileSize size;
@end

@interface LQSSettings : NSObject
@property (nonatomic, readonly) BOOL enabled;          // master switch, default NO
@property (nonatomic, readonly) BOOL editorEnabled;    // default YES
@property (nonatomic, readonly) BOOL demoStates;       // default NO
@property (nonatomic, readonly) BOOL haptics;          // default YES
@property (nonatomic, readonly) BOOL showAutoBrightness; // Lineage qs_show_auto_brightness, default YES
@property (nonatomic, readonly) BOOL showNotifications;
@property (nonatomic, readonly) BOOL blurSurfaces;       // iOS extra: frosted tiles / notifications, default NO  // notification list under QQS, default YES
+ (instancetype)current; // re-reads CFPreferences every call
@end

@interface LQSModel : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<LQSTileSpec *> *catalog;
@property (nonatomic, readonly) NSArray<LQSTileEntry *> *layout;
- (nullable LQSTileSpec *)specForIdentifier:(NSString *)identifier;
- (NSArray<LQSTileSpec *> *)availableSpecs;
- (void)setLayout:(NSArray<LQSTileEntry *> *)layout;
- (void)resetLayout;
- (void)reloadLayoutFromPreferences;
+ (NSArray<LQSTileEntry *> *)defaultLayout;
// Mock state for the preview / demo mode, never mirrored to iOS.
- (BOOL)isOn:(NSString *)identifier;
- (void)setOn:(BOOL)on forIdentifier:(NSString *)identifier;
@property (nonatomic) CGFloat mockBrightness;
@end

NS_ASSUME_NONNULL_END
