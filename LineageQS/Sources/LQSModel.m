#import "LQSStrings.h"
#import "LQSModel.h"

NSString *const LQSPrefsDomain = @"com.makr.lineageqs";
NSString *const LQSPrefsChangedNotification = @"com.makr.lineageqs/prefs-changed";
NSString *const LQSLayoutResetNotification = @"com.makr.lineageqs/reset-layout";
NSString *const LQSStateDirectory = @"/var/mobile/Library/LineageQS";
NSString *const LQSKillSwitchPath = @"/var/mobile/Library/LineageQS/DISABLE";

static NSString *const kLayoutKey = @"layout";

static id PrefValue(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)LQSPrefsDomain));
}

static BOOL PrefBool(NSString *key, BOOL def) {
    id v = PrefValue(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}

NSInteger LQSTileSpan(LQSTileSize size) { return size == LQSTileSizeLarge ? 2 : 1; }
const NSUInteger LQSMinimumTiles = 6;

NSArray<NSString *> *LQSTileCategories(void) { return @[@"connectivity", @"utilities", @"display", @"privacy", @"accessibility"]; }

NSString *LQSTileCategory(NSString *ident) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{@"internet": @"connectivity", @"wifi": @"connectivity", @"cell": @"connectivity", @"bt": @"connectivity", @"airplane": @"connectivity",
              @"cast": @"connectivity", @"hotspot": @"connectivity", @"saver": @"connectivity",
              @"flashlight": @"utilities", @"alarm": @"utilities", @"battery": @"utilities", @"controls": @"utilities", @"dnd": @"utilities",
              @"qr_code_scanner": @"utilities", @"wallet": @"utilities", @"ringer": @"utilities",
              @"rotation": @"display", @"screenrecord": @"display", @"dark": @"display", @"night": @"display",
              @"location": @"privacy", @"inversion": @"accessibility"};
    });
    return m[ident] ?: @"utilities";
}

@interface LQSTileSpec ()
@property (nonatomic, copy, readwrite) NSString *identifier, *title, *iconOn, *iconOff;
@property (nonatomic, readwrite) BOOL dualTarget, toggleable;
@end

@implementation LQSTileSpec
+ (instancetype)spec:(NSString *)ident title:(NSString *)titleRes on:(NSString *)on off:(nullable NSString *)off toggle:(BOOL)toggle dual:(BOOL)dual {
    LQSTileSpec *s = [self new];
    s.identifier = ident;
    s.title = LQSL(titleRes);
    s.iconOn = on;
    s.iconOff = off ?: on;
    s.toggleable = toggle;
    s.dualTarget = dual;
    return s;
}
@end

@implementation LQSTileEntry
+ (instancetype)entry:(NSString *)ident size:(LQSTileSize)size {
    LQSTileEntry *e = [self new];
    e.identifier = ident;
    e.size = size;
    return e;
}
- (id)copyWithZone:(NSZone *)zone { return [LQSTileEntry entry:self.identifier size:self.size]; }
- (NSDictionary *)plist { return @{@"id": self.identifier, @"size": self.size == LQSTileSizeLarge ? @"large" : @"small"}; }
@end

@implementation LQSSettings {
    BOOL _enabled, _editorEnabled, _demoStates, _haptics, _showAutoBrightness, _showNotifications, _blurSurfaces;
}
+ (instancetype)current {
    LQSSettings *s = [self new];
    s->_enabled = PrefBool(@"enabled", NO);
    s->_editorEnabled = PrefBool(@"editorEnabled", YES);
    s->_demoStates = PrefBool(@"demoStates", NO);
    s->_haptics = PrefBool(@"haptics", YES);
    s->_showAutoBrightness = PrefBool(@"showAutoBrightness", YES);
    s->_showNotifications = PrefBool(@"showNotifications", YES);
    s->_blurSurfaces = PrefBool(@"blurSurfaces", NO);
    return s;
}
- (BOOL)enabled { return _enabled; }
- (BOOL)editorEnabled { return _editorEnabled; }
- (BOOL)demoStates { return _demoStates; }
- (BOOL)haptics { return _haptics; }
- (BOOL)showAutoBrightness { return _showAutoBrightness; }
- (BOOL)showNotifications { return _showNotifications; }
- (BOOL)blurSurfaces { return _blurSurfaces; }
@end

@implementation LQSModel {
    NSArray<LQSTileSpec *> *_catalog;
    NSArray<LQSTileEntry *> *_layout;
    NSMutableDictionary<NSString *, NSNumber *> *_mockState;
}

+ (instancetype)shared {
    static LQSModel *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [LQSModel new]; });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        // Labels and icons from the tile implementations in SystemUI
        // src/com/android/systemui/qs/tiles (docs/qs-tiles-tokens.md). Only tiles
        // that iOS can back (LQSBackends) or launch are listed; "ringer" is an
        // iOS addition (Android has it in the volume panel, not QS).
        _catalog = @[
            [LQSTileSpec spec:@"internet" title:@"quick_settings_internet_label" on:@"ic_wifi_3" off:@"ic_qs_wifi_disconnected" toggle:NO dual:NO],
            [LQSTileSpec spec:@"bt" title:@"quick_settings_bluetooth_label" on:@"qs_bluetooth_icon_on" off:@"qs_bluetooth_icon_off" toggle:YES dual:YES],
            [LQSTileSpec spec:@"dnd" title:@"quick_settings_dnd_label" on:@"qs_dnd_icon_on" off:@"qs_dnd_icon_off" toggle:YES dual:YES],
            [LQSTileSpec spec:@"cast" title:@"quick_settings_cast_title" on:@"ic_cast_connected" off:@"ic_cast" toggle:NO dual:NO],
            [LQSTileSpec spec:@"flashlight" title:@"quick_settings_flashlight_label" on:@"qs_flashlight_icon_on" off:@"qs_flashlight_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"airplane" title:@"airplane_mode" on:@"qs_airplane_icon_on" off:@"qs_airplane_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"rotation" title:@"quick_settings_rotation_unlocked_label" on:@"qs_auto_rotate_icon_on" off:@"qs_auto_rotate_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"wallet" title:@"wallet_title" on:@"ic_wallet_lockscreen" off:nil toggle:NO dual:NO],
            [LQSTileSpec spec:@"alarm" title:@"status_bar_alarm" on:@"ic_alarm" off:nil toggle:NO dual:NO],
            [LQSTileSpec spec:@"controls" title:@"quick_controls_title" on:@"controls_icon" off:nil toggle:NO dual:NO],
            [LQSTileSpec spec:@"screenrecord" title:@"quick_settings_screen_record_label" on:@"qs_screen_record_icon_on" off:@"qs_screen_record_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"battery" title:@"battery_detail_switch_title" on:@"qs_battery_saver_icon_on" off:@"qs_battery_saver_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"wifi" title:@"quick_settings_wifi_label" on:@"ic_wifi_3" off:@"ic_qs_wifi_disconnected" toggle:YES dual:YES],
            [LQSTileSpec spec:@"cell" title:@"quick_settings_cellular_detail_title" on:@"ic_signal_cellular_4_4_bar" off:@"ic_signal_mobile_data_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"hotspot" title:@"quick_settings_hotspot_label" on:@"qs_hotspot_icon_on" off:@"qs_hotspot_icon_off" toggle:NO dual:NO],
            [LQSTileSpec spec:@"inversion" title:@"quick_settings_inversion_label" on:@"qs_invert_colors_icon_on" off:@"qs_invert_colors_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"saver" title:@"data_saver" on:@"qs_data_saver_icon_on" off:@"qs_data_saver_icon_off" toggle:NO dual:NO],
            [LQSTileSpec spec:@"dark" title:@"quick_settings_ui_mode_night_label" on:@"qs_light_dark_theme_icon_on" off:@"qs_light_dark_theme_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"night" title:@"quick_settings_night_display_label" on:@"qs_nightlight_icon_on" off:@"qs_nightlight_icon_off" toggle:YES dual:NO],
            [LQSTileSpec spec:@"location" title:@"quick_settings_location_label" on:@"qs_location_icon_on" off:@"qs_location_icon_off" toggle:NO dual:NO],
            [LQSTileSpec spec:@"qr_code_scanner" title:@"qr_code_scanner_title" on:@"ic_qr_code_scanner" off:nil toggle:NO dual:NO],
            [LQSTileSpec spec:@"ringer" title:@"Ring" on:@"ic_mobile_vibrate" off:nil toggle:YES dual:NO],
        ];
        _mockState = [NSMutableDictionary dictionary];
        for (NSString *k in @[@"internet", @"bt", @"rotation", @"wifi", @"cell", @"dark", @"ringer"]) _mockState[k] = @YES;
        _mockBrightness = 0.55;
        [self reloadLayoutFromPreferences];
    }
    return self;
}

- (NSArray<LQSTileSpec *> *)catalog { return _catalog; }
- (NSArray<LQSTileEntry *> *)layout { return _layout; }

- (LQSTileSpec *)specForIdentifier:(NSString *)identifier {
    for (LQSTileSpec *s in _catalog) if ([s.identifier isEqualToString:identifier]) return s;
    return nil;
}

- (NSArray<LQSTileSpec *> *)availableSpecs {
    NSMutableSet *used = [NSMutableSet set];
    for (LQSTileEntry *e in _layout) [used addObject:e.identifier];
    NSMutableArray *out = [NSMutableArray array];
    for (LQSTileSpec *s in _catalog) if (![used containsObject:s.identifier]) [out addObject:s];
    return out;
}

+ (NSArray<LQSTileEntry *> *)defaultLayout {
    // config.xml:82-85 quick_settings_tiles_default (Android 17.0 / cp1a: no
    // internet split, docs/qs-tiles-tokens.md); large: DefaultLargeTilesRepository.kt:44-49.
    NSArray *order = @[@"internet", @"bt", @"dnd", @"cast", @"flashlight", @"airplane", @"rotation", @"wallet", @"alarm", @"controls", @"screenrecord", @"battery"];
    NSSet *large = [NSSet setWithArray:@[@"internet", @"bt", @"dnd", @"cast"]];
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *ident in order) [a addObject:[LQSTileEntry entry:ident size:[large containsObject:ident] ? LQSTileSizeLarge : LQSTileSizeSmall]];
    return a;
}

- (void)reloadLayoutFromPreferences {
    id raw = PrefValue(kLayoutKey);
    NSMutableArray *parsed = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if ([raw isKindOfClass:NSArray.class]) {
        for (NSDictionary *d in raw) {
            if (![d isKindOfClass:NSDictionary.class]) continue;
            NSString *ident = d[@"id"];
            if (![ident isKindOfClass:NSString.class] || ![self specForIdentifier:ident] || [seen containsObject:ident]) continue;
            [seen addObject:ident];
            [parsed addObject:[LQSTileEntry entry:ident size:[d[@"size"] isEqual:@"large"] ? LQSTileSizeLarge : LQSTileSizeSmall]];
        }
    }
    _layout = parsed.count ? parsed : [LQSModel defaultLayout];
}

- (void)persist:(NSArray<LQSTileEntry *> *)layout {
    NSMutableArray *plist = [NSMutableArray array];
    for (LQSTileEntry *e in layout) [plist addObject:[e plist]];
    CFPreferencesSetAppValue((__bridge CFStringRef)kLayoutKey, (__bridge CFArrayRef)plist, (__bridge CFStringRef)LQSPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
}

- (void)setLayout:(NSArray<LQSTileEntry *> *)layout {
    _layout = [[NSArray alloc] initWithArray:layout copyItems:YES];
    [self persist:_layout];
}

- (void)resetLayout {
    _layout = [LQSModel defaultLayout];
    CFPreferencesSetAppValue((__bridge CFStringRef)kLayoutKey, NULL, (__bridge CFStringRef)LQSPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
}

- (BOOL)isOn:(NSString *)identifier { return [_mockState[identifier] boolValue]; }
- (void)setOn:(BOOL)on forIdentifier:(NSString *)identifier { _mockState[identifier] = @(on); }

@end
