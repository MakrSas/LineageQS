// Real iOS backends for tiles (SpringBoard process only). Every call is
// resolved at runtime; if a class/selector is missing the tile reports
// LQSBackendStateUnsupported and stays a visual mock. See
// docs/research-tile-backends.md for the API evidence of each backend.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LQSBackendState) {
    LQSBackendStateUnsupported = -2, // no backend: demo/mock only
    LQSBackendStateUnavailable = -1, // hardware absent (Glyph, NFC toggle) or blocked
    LQSBackendStateOff = 0,
    LQSBackendStateOn = 1,
};

typedef NS_ENUM(NSInteger, LQSBackendKind) {
    LQSBackendKindToggle,  // on/off with readback
    LQSBackendKindLaunch,  // opens an app (Wallet, QR, Alarm)
};

@interface LQSBackends : NSObject
+ (BOOL)realActionsEnabled;                       // settings key realActions (default NO)
+ (LQSBackendKind)kindFor:(NSString *)identifier;
+ (LQSBackendState)stateFor:(NSString *)identifier;
+ (BOOL)isTransitioning:(NSString *)identifier;
+ (NSInteger)recordingCountdown; // 3...1 before starting; zero otherwise
+ (void)prepare; // load optional recording classes before Logos installs hooks
+ (void)recordingStateChanged:(BOOL)recording;
// Toggles / launches. Returns the state read back afterwards (may lag: the
// caller should refresh again shortly).
+ (LQSBackendState)activate:(NSString *)identifier;
+ (BOOL)setOn:(BOOL)on forIdentifier:(NSString *)identifier;
// Brightness 0...1 (SBDisplayBrightnessController); <0 when unsupported.
+ (BOOL)brightnessControlSupported; // currently NO: see LQSBackends.m
+ (CGFloat)brightness;
+ (void)setBrightness:(CGFloat)value;
// Long press: open the iOS Settings page that matches the tile.
+ (nullable NSString *)settingsURLFor:(NSString *)identifier;
+ (BOOL)openSettingsFor:(NSString *)identifier;
// Live, read-only connectivity info for labels and the header row:
//  wifiOn, wifiAssociated, wifiName, wifiBars (0-3)
//  noSIM, carrier, network ("LTE"), cellBars (0-4), fakeSIM (values from the FakeSIM tweak)
//  btDevice, btBattery (-1 unknown), focusName
+ (NSDictionary<NSString *, id> *)liveInfo;
// Secondary label for a tile from liveInfo, nil = use the default text.
+ (nullable NSString *)secondaryLabelFor:(NSString *)identifier info:(NSDictionary *)info;
// Detail panels (long press). Wi-Fi via MobileWiFi C API (symbols verified on
// device 2026-10-17); Bluetooth via BluetoothManager / BluetoothDevice.
// Network dict: ssid, rssi (dBm, NSNumber), secure (BOOL), known (BOOL), current (BOOL), bars (0-3)
+ (void)scanWiFiWithCompletion:(void (^)(NSArray<NSDictionary *> *networks))completion;
+ (BOOL)joinWiFi:(NSString *)ssid; // known networks only; NO = needs Settings (password)
+ (void)disconnectWiFi;
// Device dict: name, connected (BOOL), battery (int, -1), kind ("headphones"/"watch"/"phone"/"computer"/"other"), address
+ (NSArray<NSDictionary *> *)bluetoothDevices;
+ (BOOL)setBluetoothDevice:(NSString *)address connected:(BOOL)connected;
// Logs a class's methods with type encodings (debug).
+ (NSString *)dumpClass:(NSString *)name;
@end

FOUNDATION_EXTERN NSString *const LQSBackendsChangedNotification; // local NSNotification

NS_ASSUME_NONNULL_END
