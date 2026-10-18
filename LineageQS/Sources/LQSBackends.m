#import "LQSStrings.h"
#import "LQSBackends.h"
#import "LQSModel.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

NSString *const LQSBackendsChangedNotification = @"LQSBackendsChangedNotification";

static id Shared(NSString *cls, NSString *sel) {
    Class c = NSClassFromString(cls);
    SEL s = NSSelectorFromString(sel);
    if (!c || ![c respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(c, s);
}

static BOOL Has(id obj, NSString *sel) { return obj && [obj respondsToSelector:NSSelectorFromString(sel)]; }
static BOOL GetBool(id obj, NSString *sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel)); }
static void SetBool(id obj, NSString *sel, BOOL v) { ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, NSSelectorFromString(sel), v); }
static void Call0(id obj, NSString *sel) { ((void (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel)); }

static void LoadFramework(const char *path) {
    static NSMutableSet *loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loaded = [NSMutableSet set]; });
    NSString *k = @(path);
    if ([loaded containsObject:k]) return;
    [loaded addObject:k];
    dlopen(path, RTLD_LAZY);
}

static LQSBackendState B(BOOL on) { return on ? LQSBackendStateOn : LQSBackendStateOff; }

#pragma mark - Individual backends

// Wi-Fi: SBWiFiManager (SpringBoard.objc:85982 / 85999 / 86012).
static id WiFi(void) { return Shared(@"SBWiFiManager", @"sharedInstance"); }

// Bluetooth: BluetoothManager.framework (+sharedInstance, powered, setPowered:).
static id Bluetooth(void) {
    LoadFramework("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager");
    return Shared(@"BluetoothManager", @"sharedInstance");
}

// Airplane: SBAirplaneModeController (SpringBoard.objc:16193 / 16197 / 16200).
static id Airplane(void) { return Shared(@"SBAirplaneModeController", @"sharedInstance"); }

// Rotation: SBOrientationLockManager (SpringBoard.objc:59557 / 59582 / 59571 / 59561).
static id Orientation(void) { return Shared(@"SBOrientationLockManager", @"sharedInstance"); }

// Flashlight: SBUIFlashlightController (SpringBoardUIServices).
static id Flashlight(void) {
    LoadFramework("/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/SpringBoardUIServices");
    return Shared(@"SBUIFlashlightController", @"sharedInstance");
}

// Dark mode: UIUserInterfaceStyleArbiter (UIKitCore).
static id StyleArbiter(void) { return Shared(@"UIUserInterfaceStyleArbiter", @"sharedInstance"); }

// Ringer: SBControlCenterSystemAgent (isRingerMuted / setRingerMuted:), the object
// SBControlCenterController hands to stock CC modules.
static id SystemAgent(void) {
    id cc = Shared(@"SBControlCenterController", @"sharedInstanceIfExists");
    return Has(cc, @"systemAgent") ? ((id (*)(id, SEL))objc_msgSend)(cc, NSSelectorFromString(@"systemAgent")) : nil;
}

// Night Shift: CBBlueLightClient (CoreBrightness). getBlueLightStatus: fills
// {BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode; schedule; uint64 flags; BOOL available}.
typedef struct { BOOL active, enabled, sunSchedulePermitted; int mode; struct { struct { int h, m; } from, to; } schedule; unsigned long long disableFlags; BOOL available; } LQSBlueLightStatus;
static id BlueLight(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LoadFramework("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness");
        Class c = NSClassFromString(@"CBBlueLightClient");
        client = c ? [c new] : nil;
    });
    return client;
}

// Focus / Do Not Disturb: FCActivityManager (Focus.framework).
static id Focus(void) {
    LoadFramework("/System/Library/PrivateFrameworks/Focus.framework/Focus");
    return Shared(@"FCActivityManager", @"sharedActivityManager");
}

// Screen recording: RPControlCenterClient (ReplayKit), same client the stock module uses.
static id Recorder(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LoadFramework("/System/Library/Frameworks/ReplayKit.framework/ReplayKit");
        // RPControlCenterClient lives in the CC bundle, not ReplayKit.framework.
        LoadFramework("/System/Library/ControlCenter/Bundles/ReplayKitModule.bundle/ReplayKitModule");
        Class c = NSClassFromString(@"RPControlCenterClient");
        if ([c respondsToSelector:NSSelectorFromString(@"sharedInstance")]) client = ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedInstance"));
        else client = c ? [c new] : nil;
    });
    return client;
}

// Low Power Mode: iOS 16 LowPowerMode.framework (_PMLowPowerMode); the older
// CoreDuet _CDBatterySaver class is absent on this device.
static id BatterySaver(void) {
    LoadFramework("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode");
    id client = Shared(@"_PMLowPowerMode", @"sharedInstance");
    if (!client) {
        LoadFramework("/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet");
        client = Shared(@"_CDBatterySaver", @"batterySaver"); // iOS 15 fallback
    }
    return client;
}

// Cellular data: CoreTelephony C API used by the stock CC connectivity module.
typedef const void *CTConn;
static CTConn CTConnection(void) {
    static CTConn conn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
        CTConn (*create)(CFAllocatorRef, CFStringRef, void *, void *) = (CTConn (*)(CFAllocatorRef, CFStringRef, void *, void *))dlsym(h, "_CTServerConnectionCreateWithIdentifier");
        if (create) conn = create(kCFAllocatorDefault, CFSTR("com.makr.lineageqs"), NULL, NULL);
    });
    return conn;
}
static int CellularRead(void) {
    CTConn c = CTConnection();
    void *h = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    uint64_t (*get)(CTConn, Boolean *) = (uint64_t (*)(CTConn, Boolean *))dlsym(h, "_CTServerConnectionGetCellularDataIsEnabled");
    if (!c || !get) return -1;
    Boolean on = false;
    uint64_t err = get(c, &on);
    return err == 0 ? (on ? 1 : 0) : -1;
}
static BOOL CellularSet(BOOL on) {
    CTConn c = CTConnection();
    void *h = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    uint64_t (*set)(CTConn, Boolean) = (uint64_t (*)(CTConn, Boolean))dlsym(h, "_CTServerConnectionSetCellularDataIsEnabled");
    return c && set && set(c, on) == 0;
}

// Classic colour inversion: libAccessibility.
static BOOL (*AXInvertGet)(void);
static void (*AXInvertSet)(BOOL);
static BOOL LoadAX(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LAZY);
        AXInvertGet = (BOOL (*)(void))dlsym(h, "_AXSClassicInvertColorsEnabled");
        AXInvertSet = (void (*)(BOOL))dlsym(h, "_AXSClassicInvertColorsSetEnabled");
    });
    return AXInvertGet && AXInvertSet;
}

// ---- MobileWiFi (C API). Callback arguments are type-checked before use.
typedef const void *WiFiRef;
static void *WiFiLib(void) {
    static void *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY); });
    return h;
}
#define WIFI_FN(ret, name, ...) static ret (*name##_)(__VA_ARGS__); if (!name##_) name##_ = (ret (*)(__VA_ARGS__))dlsym(WiFiLib(), #name);

static WiFiRef WiFiClient(void) {
    static WiFiRef client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WIFI_FN(WiFiRef, WiFiManagerClientCreate, CFAllocatorRef, int);
        WIFI_FN(void, WiFiManagerClientScheduleWithRunLoop, WiFiRef, CFRunLoopRef, CFStringRef);
        if (WiFiManagerClientCreate_) client = WiFiManagerClientCreate_(kCFAllocatorDefault, 0);
        if (client && WiFiManagerClientScheduleWithRunLoop_) WiFiManagerClientScheduleWithRunLoop_(client, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    });
    return client;
}

static WiFiRef WiFiDevice(void) {
    static WiFiRef device;
    if (device) return device;
    WIFI_FN(CFArrayRef, WiFiManagerClientCopyDevices, WiFiRef);
    WiFiRef c = WiFiClient();
    CFArrayRef devs = (c && WiFiManagerClientCopyDevices_) ? WiFiManagerClientCopyDevices_(c) : NULL;
    if (devs && CFGetTypeID(devs) == CFArrayGetTypeID() && CFArrayGetCount(devs) > 0) device = CFRetain(CFArrayGetValueAtIndex(devs, 0));
    if (devs) CFRelease(devs);
    return device;
}

static NSString *WiFiSSID(WiFiRef net) {
    WIFI_FN(CFStringRef, WiFiNetworkGetSSID, WiFiRef);
    CFStringRef s = (net && WiFiNetworkGetSSID_) ? WiFiNetworkGetSSID_(net) : NULL;
    return (s && CFGetTypeID(s) == CFStringGetTypeID()) ? (__bridge NSString *)s : nil;
}

static NSDictionary *WiFiNetworkInfo(WiFiRef net, NSSet *known, NSString *current) {
    NSString *ssid = WiFiSSID(net);
    if (!ssid.length) return nil;
    WIFI_FN(CFTypeRef, WiFiNetworkGetProperty, WiFiRef, CFStringRef);
    WIFI_FN(Boolean, WiFiNetworkIsWPA, WiFiRef);
    WIFI_FN(Boolean, WiFiNetworkIsWEP, WiFiRef);
    WIFI_FN(Boolean, WiFiNetworkIsEAP, WiFiRef);
    CFTypeRef r = WiFiNetworkGetProperty_ ? WiFiNetworkGetProperty_(net, CFSTR("RSSI")) : NULL;
    NSInteger rssi = (r && CFGetTypeID(r) == CFNumberGetTypeID()) ? [(__bridge NSNumber *)r integerValue] : -80;
    BOOL secure = (WiFiNetworkIsWPA_ && WiFiNetworkIsWPA_(net)) || (WiFiNetworkIsWEP_ && WiFiNetworkIsWEP_(net)) || (WiFiNetworkIsEAP_ && WiFiNetworkIsEAP_(net));
    // Android WifiIcons levels from RSSI (assumption: -55/-66/-77 thresholds, 4 levels -> ic_wifi_0..3)
    NSInteger bars = rssi >= -55 ? 3 : rssi >= -66 ? 2 : rssi >= -77 ? 1 : 0;
    return @{@"ssid": ssid, @"rssi": @(rssi), @"secure": @(secure), @"known": @([known containsObject:ssid]),
             @"current": @([ssid isEqualToString:current]), @"bars": @(bars)};
}

static void (^gScanCompletion)(NSArray *);
static void WiFiScanCallback(WiFiRef device, CFTypeRef results, void *err, void *ctx) {
    NSMutableArray *list = [NSMutableArray array];
    WIFI_FN(CFArrayRef, WiFiManagerClientCopyNetworks, WiFiRef);
    NSMutableSet *known = [NSMutableSet set];
    CFArrayRef kn = (WiFiClient() && WiFiManagerClientCopyNetworks_) ? WiFiManagerClientCopyNetworks_(WiFiClient()) : NULL;
    if (kn && CFGetTypeID(kn) == CFArrayGetTypeID()) for (CFIndex i = 0; i < CFArrayGetCount(kn); i++) { NSString *ss = WiFiSSID(CFArrayGetValueAtIndex(kn, i)); if (ss) [known addObject:ss]; }
    if (kn) CFRelease(kn);
    NSString *current = nil;
    id w = Shared(@"SBWiFiManager", @"sharedInstance");
    if ([w respondsToSelector:NSSelectorFromString(@"currentNetworkName")]) current = ((id (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"currentNetworkName"));
    NSMutableSet *seen = [NSMutableSet set];
    if (results && CFGetTypeID(results) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(results); i++) {
            NSDictionary *d = WiFiNetworkInfo(CFArrayGetValueAtIndex(results, i), known, current);
            if (d && ![seen containsObject:d[@"ssid"]]) { [seen addObject:d[@"ssid"]]; [list addObject:d]; }
        }
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"current"] boolValue] != [b[@"current"] boolValue]) return [a[@"current"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        if ([a[@"known"] boolValue] != [b[@"known"] boolValue]) return [a[@"known"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        return [b[@"rssi"] compare:a[@"rssi"]];
    }];
    void (^done)(NSArray *) = gScanCompletion;
    gScanCompletion = nil;
    if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(list); });
}

static NSString *LaunchBundleFor(NSString *ident) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"wallet": @"com.apple.Passbook", @"qr_code_scanner": @"com.apple.BarcodeScanner", @"alarm": @"com.apple.mobiletimer", @"controls": @"com.apple.Home"};
    });
    return map[ident];
}

// Main-thread state shared by tiles and detail dialogs. Keep the requested
// state until hardware acknowledges it, or roll back after a bounded timeout.
static NSMutableDictionary<NSString *, NSDictionary *> *gPending;
static NSTimer *gPendingTimer, *gCountdownTimer;
static NSTimeInterval gCountdownDeadline;
static BOOL gRecordingStateKnown, gRecordingOn;

@implementation LQSBackends

+ (void)prepare { Recorder(); }

+ (void)postChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LQSBackendsChangedNotification object:nil];
}

+ (void)recordingStateChanged:(BOOL)recording {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL stopped = gRecordingStateKnown && gRecordingOn && !recording;
        gRecordingStateKnown = YES;
        gRecordingOn = recording;
        NSDictionary *pending = gPending[@"screenrecord"];
        if (stopped || (pending && [pending[@"on"] boolValue] == recording)) [gPending removeObjectForKey:@"screenrecord"];
        if (recording) { [gCountdownTimer invalidate]; gCountdownTimer = nil; gCountdownDeadline = 0; }
        [self postChanged];
    });
}

+ (NSInteger)recordingCountdown {
    return MAX(0, (NSInteger)ceil(gCountdownDeadline - NSProcessInfo.processInfo.systemUptime));
}

+ (LQSBackendState)stateFor:(NSString *)ident {
    if ([ident isEqualToString:@"screenrecord"] && [self recordingCountdown] > 0) return LQSBackendStateOn;
    LQSBackendState actual = [self hardwareStateFor:ident];
    NSDictionary *pending = gPending[ident];
    if (!pending) return actual;
    LQSBackendState target = [pending[@"on"] boolValue] ? LQSBackendStateOn : LQSBackendStateOff;
    if (actual == target || [pending[@"deadline"] doubleValue] <= NSProcessInfo.processInfo.systemUptime || actual < 0) {
        [gPending removeObjectForKey:ident];
        return actual;
    }
    return target;
}

+ (BOOL)isTransitioning:(NSString *)ident {
    [self stateFor:ident]; // reconcile before reporting
    return gPending[ident] != nil;
}

+ (void)pollPendingChanges {
    for (NSString *ident in gPending.allKeys) [self stateFor:ident];
    [self postChanged];
    if (!gPending.count) { [gPendingTimer invalidate]; gPendingTimer = nil; }
}

+ (void)trackRequest:(BOOL)on identifier:(NSString *)ident {
    if (!gPending) gPending = [NSMutableDictionary dictionary];
    gPending[ident] = @{@"on": @(on), @"deadline": @(NSProcessInfo.processInfo.systemUptime + 8)};
    if (!gPendingTimer) {
        gPendingTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) { [self pollPendingChanges]; }];
        [NSRunLoop.mainRunLoop addTimer:gPendingTimer forMode:NSRunLoopCommonModes];
    }
    [self postChanged];
}

+ (BOOL)setOn:(BOOL)on forIdentifier:(NSString *)ident {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return NO;
    if ([ident isEqualToString:@"screenrecord"]) {
        if (gCountdownTimer) {
            [gCountdownTimer invalidate]; gCountdownTimer = nil; gCountdownDeadline = 0;
            [self postChanged];
            if (!on) return YES; // cancelled before ReplayKit was started
        }
        if (on) {
            id r = Recorder();
            if (!Has(r, @"startRecordingWithHandler:")) return NO;
            if ([self hardwareStateFor:ident] == LQSBackendStateOn) return YES;
            gCountdownDeadline = NSProcessInfo.processInfo.systemUptime + 3;
            gCountdownTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
                if (![self realActionsEnabled] || ![LQSSettings current].enabled) {
                    [t invalidate]; gCountdownTimer = nil; gCountdownDeadline = 0;
                    [self postChanged];
                    return;
                }
                if ([self recordingCountdown] == 0) {
                    [t invalidate]; gCountdownTimer = nil; gCountdownDeadline = 0;
                    if ([self setHardwareOn:YES forIdentifier:@"screenrecord"]) [self trackRequest:YES identifier:@"screenrecord"];
                }
                [self postChanged];
            }];
            [NSRunLoop.mainRunLoop addTimer:gCountdownTimer forMode:NSRunLoopCommonModes];
            [self postChanged];
            return YES;
        }
    }
    if (![self setHardwareOn:on forIdentifier:ident]) return NO;
    [self trackRequest:on identifier:ident];
    return YES;
}

+ (BOOL)realActionsEnabled {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("realActions"), (__bridge CFStringRef)LQSPrefsDomain));
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

+ (LQSBackendKind)kindFor:(NSString *)identifier {
    return LaunchBundleFor(identifier) ? LQSBackendKindLaunch : LQSBackendKindToggle;
}

+ (LQSBackendState)hardwareStateFor:(NSString *)ident {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return LQSBackendStateUnsupported;
    @try {
        if ([@[@"glyphs", @"glyphs_torch", @"nfc", @"batteryshare"] containsObject:ident]) return LQSBackendStateUnavailable; // no such hardware on iPhone 8
        // No iOS 16 setter found (hotspot: no API in dumps; data saver: per-network
        // Low Data Mode; cast: route picker): tap opens the matching settings page.
        if ([@[@"hotspot", @"saver", @"cast", @"location", @"internet"] containsObject:ident]) return LQSBackendStateUnsupported;
        if (LaunchBundleFor(ident)) return LQSBackendStateOff;
        if ([ident isEqualToString:@"wifi"]) { id w = WiFi(); if (Has(w, @"wiFiEnabled")) return B(GetBool(w, @"wiFiEnabled")); }
        if ([ident isEqualToString:@"bt"]) { id b = Bluetooth(); if (Has(b, @"powered")) return B(GetBool(b, @"powered")); }
        if ([ident isEqualToString:@"airplane"]) { id a = Airplane(); if (Has(a, @"isInAirplaneMode")) return B(GetBool(a, @"isInAirplaneMode")); }
        if ([ident isEqualToString:@"rotation"]) {
            // The Android tile is "Auto-rotate": ON means rotation is NOT locked.
            id o = Orientation(); if (Has(o, @"isUserLocked")) return B(!GetBool(o, @"isUserLocked"));
        }
        if ([ident isEqualToString:@"flashlight"]) {
            id f = Flashlight();
            if (Has(f, @"isAvailable") && !GetBool(f, @"isAvailable")) return LQSBackendStateUnavailable;
            // On-device dump: -level Q16@0:8 (unsigned integer level, 0 = off).
            if (Has(f, @"level")) return B(((unsigned long long (*)(id, SEL))objc_msgSend)(f, NSSelectorFromString(@"level")) > 0);
        }
        if ([ident isEqualToString:@"dark"]) {
            id s = StyleArbiter();
            if (Has(s, @"currentStyle")) return B(((long long (*)(id, SEL))objc_msgSend)(s, NSSelectorFromString(@"currentStyle")) == UIUserInterfaceStyleDark);
        }
        if ([ident isEqualToString:@"battery"]) return B(NSProcessInfo.processInfo.isLowPowerModeEnabled);
        if ([ident isEqualToString:@"ringer"]) { id a = SystemAgent(); if (Has(a, @"isRingerMuted")) return B(!GetBool(a, @"isRingerMuted")); } // tile ON = ringing
        if ([ident isEqualToString:@"night"]) {
            id b = BlueLight(); LQSBlueLightStatus st = {0};
            if (Has(b, @"getBlueLightStatus:") && ((BOOL (*)(id, SEL, LQSBlueLightStatus *))objc_msgSend)(b, NSSelectorFromString(@"getBlueLightStatus:"), &st)) return B(st.active);
        }
        if ([ident isEqualToString:@"dnd"]) { id f = Focus(); if (Has(f, @"activeActivity")) return B(((id (*)(id, SEL))objc_msgSend)(f, NSSelectorFromString(@"activeActivity")) != nil); }
        if ([ident isEqualToString:@"screenrecord"]) {
            if (gRecordingStateKnown) return B(gRecordingOn);
            id r = Shared(@"RPScreenRecorder", @"sharedRecorder");
            if (Has(r, @"systemRecording")) return B(GetBool(r, @"systemRecording"));
            r = Recorder();
            if (Has(r, @"recordingOn")) return B(GetBool(r, @"recordingOn"));
        }
        if ([ident isEqualToString:@"cell"]) { int v = CellularRead(); if (v >= 0) return B(v); }
        if ([ident isEqualToString:@"inversion"]) { if (LoadAX()) return B(AXInvertGet()); }
    } @catch (NSException *e) {
        NSLog(@"[LineageQS] backend %@ read exception %@", ident, e);
    }
    return LQSBackendStateUnsupported;
}

+ (BOOL)setHardwareOn:(BOOL)on forIdentifier:(NSString *)ident {
    @try {
        if ([ident isEqualToString:@"wifi"]) { id w = WiFi(); if (Has(w, @"setWiFiEnabled:")) { SetBool(w, @"setWiFiEnabled:", on); return YES; } }
        if ([ident isEqualToString:@"bt"]) {
            id b = Bluetooth();
            if (Has(b, @"setPowered:")) { SetBool(b, @"setPowered:", on); if (Has(b, @"setEnabled:")) SetBool(b, @"setEnabled:", on); return YES; }
        }
        if ([ident isEqualToString:@"airplane"]) { id a = Airplane(); if (Has(a, @"setInAirplaneMode:")) { SetBool(a, @"setInAirplaneMode:", on); return YES; } }
        if ([ident isEqualToString:@"rotation"]) {
            id o = Orientation();
            if (on && Has(o, @"unlock")) { Call0(o, @"unlock"); return YES; }
            if (!on && Has(o, @"lock")) { Call0(o, @"lock"); return YES; }
        }
        if ([ident isEqualToString:@"flashlight"]) {
            id f = Flashlight();
            NSString *sel = on ? @"turnFlashlightOnForReason:" : @"turnFlashlightOffForReason:";
            if (Has(f, sel)) { ((void (*)(id, SEL, id))objc_msgSend)(f, NSSelectorFromString(sel), @"LineageQS"); return YES; }
        }
        if ([ident isEqualToString:@"ringer"]) { id a = SystemAgent(); if (Has(a, @"setRingerMuted:")) { SetBool(a, @"setRingerMuted:", !on); return YES; } }
        if ([ident isEqualToString:@"night"]) {
            // setEnabled: is the manual flag; with a schedule running, "active"
            // only follows setActive: (device test 2026-10-17).
            id b = BlueLight();
            if (Has(b, @"setActive:")) return ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(b, NSSelectorFromString(@"setActive:"), on);
            if (Has(b, @"setEnabled:")) return ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(b, NSSelectorFromString(@"setEnabled:"), on);
        }
        if ([ident isEqualToString:@"dnd"]) {
            id f = Focus();
            SEL sel = NSSelectorFromString(@"setActivity:active:reason:");
            id act = on ? (Has(f, @"defaultActivity") ? ((id (*)(id, SEL))objc_msgSend)(f, NSSelectorFromString(@"defaultActivity")) : nil)
                        : (Has(f, @"activeActivity") ? ((id (*)(id, SEL))objc_msgSend)(f, NSSelectorFromString(@"activeActivity")) : nil);
            if (act && [f respondsToSelector:sel]) { ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(f, sel, act, on, @"LineageQS"); return YES; }
        }
        if ([ident isEqualToString:@"screenrecord"]) {
            id r = Recorder();
            if (on && Has(r, @"startRecordingWithHandler:")) { ((void (*)(id, SEL, id))objc_msgSend)(r, NSSelectorFromString(@"startRecordingWithHandler:"), ^{ dispatch_async(dispatch_get_main_queue(), ^{ [LQSBackends pollPendingChanges]; }); }); return YES; }
            if (!on && Has(r, @"stopCurrentSession:")) { ((void (*)(id, SEL, id))objc_msgSend)(r, NSSelectorFromString(@"stopCurrentSession:"), ^{ dispatch_async(dispatch_get_main_queue(), ^{ [LQSBackends pollPendingChanges]; }); }); return YES; }
        }
        if ([ident isEqualToString:@"cell"]) return CellularSet(on);
        if ([ident isEqualToString:@"inversion"]) { if (LoadAX()) { AXInvertSet(on); return YES; } }
        if ([ident isEqualToString:@"battery"]) {
            id b = BatterySaver();
            SEL sel = NSSelectorFromString(@"setPowerMode:fromSource:");
            if ([b respondsToSelector:sel]) return ((BOOL (*)(id, SEL, long long, id))objc_msgSend)(b, sel, on ? 1 : 0, @"LineageQS");
            sel = NSSelectorFromString(@"setPowerMode:fromSource:withCompletion:");
            if ([b respondsToSelector:sel]) { ((void (*)(id, SEL, long long, id, id))objc_msgSend)(b, sel, on ? 1 : 0, @"LineageQS", ^(BOOL ok, NSError *e) { NSLog(@"[LineageQS] LPM %d %@", ok, e); }); return YES; }
        }
        if ([ident isEqualToString:@"dark"]) {
            id s = StyleArbiter();
            BOOL isDark = [self stateFor:@"dark"] == LQSBackendStateOn;
            if (isDark != on && Has(s, @"toggleCurrentStyle")) { Call0(s, @"toggleCurrentStyle"); return YES; }
            return isDark == on;
        }
    } @catch (NSException *e) {
        NSLog(@"[LineageQS] backend %@ set exception %@", ident, e);
    }
    return NO;
}

+ (LQSBackendState)activate:(NSString *)ident {
    NSString *bundle = LaunchBundleFor(ident);
    if (bundle) {
        Class ws = NSClassFromString(@"LSApplicationWorkspace");
        id w = [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"defaultWorkspace")) : nil;
        if (Has(w, @"openApplicationWithBundleID:")) ((BOOL (*)(id, SEL, id))objc_msgSend)(w, NSSelectorFromString(@"openApplicationWithBundleID:"), bundle);
        return LQSBackendStateOff;
    }
    LQSBackendState s = [self stateFor:ident];
    if (s < 0) return s;
    [self setOn:(s != LQSBackendStateOn) forIdentifier:ident];
    return [self stateFor:ident];
}

+ (NSString *)settingsURLFor:(NSString *)ident {
    // Long press = Android tile long-click (opens the feature's settings).
    // iOS 16 "prefs:" roots (assumption per page; verified on device separately).
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"wifi": @"prefs:root=WIFI", @"bt": @"prefs:root=Bluetooth", @"cell": @"prefs:root=MOBILE_DATA_SETTINGS_ID",
                @"saver": @"prefs:root=MOBILE_DATA_SETTINGS_ID", @"airplane": @"prefs:root=ROOT", @"hotspot": @"prefs:root=INTERNET_TETHERING",
                @"dnd": @"prefs:root=DO_NOT_DISTURB", @"battery": @"prefs:root=BATTERY_USAGE", @"dark": @"prefs:root=DISPLAY",
                @"night": @"prefs:root=DISPLAY&path=BLUE_LIGHT_REDUCTION", @"rotation": @"prefs:root=DISPLAY",
                @"inversion": @"prefs:root=ACCESSIBILITY&path=DISPLAY_AND_TEXT", @"ringer": @"prefs:root=Sounds",
                @"screenrecord": @"prefs:root=ControlCenter", @"cast": @"prefs:root=General&path=AIRPLAY_HANDOFF",
                @"wallet": @"prefs:root=PASSBOOK", @"flashlight": @"prefs:root=ControlCenter", @"alarm": @"clock-alarm:",
                @"qr_code_scanner": @"prefs:root=CAMERA", @"controls": @"prefs:root=ControlCenter",
                @"internet": @"prefs:root=WIFI", @"location": @"prefs:root=Privacy&path=LOCATION"};
    });
    return map[ident];
}

+ (BOOL)openSettingsFor:(NSString *)ident {
    NSString *u = [self settingsURLFor:ident];
    if (!u) return NO;
    NSURL *url = [NSURL URLWithString:u];
    // 1) SpringBoard's own URL routing (what SB uses for prefs: links).
    UIApplication *app = UIApplication.sharedApplication;
    SEL sbOpen = NSSelectorFromString(@"applicationOpenURL:");
    if ([app respondsToSelector:sbOpen]) { ((void (*)(id, SEL, id))objc_msgSend)(app, sbOpen, url); return YES; }
    // 2) Public API, 3) LaunchServices sensitive URL.
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:^(BOOL ok) { NSLog(@"[LineageQS] openURL %@ -> %d", url, ok); }];
        return YES;
    }
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    id w = [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"defaultWorkspace")) : nil;
    SEL sel = NSSelectorFromString(@"openSensitiveURL:withOptions:");
    if ([w respondsToSelector:sel]) return ((BOOL (*)(id, SEL, id, id))objc_msgSend)(w, sel, url, nil);
    return NO;
}

+ (CGFloat)brightness {
    id bc = BrightnessClient();
    if (Has(bc, @"copyPropertyForKey:")) {
        id v = ((id (*)(id, SEL, id))objc_msgSend)(bc, NSSelectorFromString(@"copyPropertyForKey:"), @"DisplayBrightness");
        if ([v isKindOfClass:NSNumber.class]) return [v doubleValue];
        if ([v isKindOfClass:NSDictionary.class] && [v[@"Brightness"] isKindOfClass:NSNumber.class]) return [v[@"Brightness"] doubleValue];
    }
    id b = Shared(@"SBDisplayBrightnessController", @"sharedInstance");
    if (Has(b, @"brightnessLevel")) return ((float (*)(id, SEL))objc_msgSend)(b, NSSelectorFromString(@"brightnessLevel"));
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return UIScreen.mainScreen.brightness;
    return -1;
}

// Brightness. BKSDisplayBrightnessSet(level, 1) crashed backboardd 3x
// (CoreBrightness CBSliderCommitTelemetry) — never use it. Verified on device
// 2026-10-17: BrightnessSystemClient setProperty:@(level) forKey:@"DisplayBrightness"
// (no commit) sets and reads back 0.5 / 0.85 and survived a 12-step burst
// with no crash. Settings key brightnessControl (default YES) can disable it.
static id BrightnessClient(void) {
    static id c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LoadFramework("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness");
        Class k = NSClassFromString(@"BrightnessSystemClient");
        c = k ? [k new] : nil;
    });
    return c;
}

+ (BOOL)brightnessControlSupported {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("brightnessControl"), (__bridge CFStringRef)LQSPrefsDomain));
    BOOL allowed = [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES;
    return allowed && [self realActionsEnabled] && Has(BrightnessClient(), @"setProperty:forKey:");
}

+ (void)setBrightness:(CGFloat)value {
    if (![self brightnessControlSupported]) return;
    float v = (float)MAX(0.0, MIN(1.0, value));
    ((BOOL (*)(id, SEL, id, id))objc_msgSend)(BrightnessClient(), NSSelectorFromString(@"setProperty:forKey:"), @(v), @"DisplayBrightness");
}

+ (void)scanWiFiWithCompletion:(void (^)(NSArray<NSDictionary *> *))completion {
    WIFI_FN(void, WiFiDeviceClientScanAsync, WiFiRef, CFDictionaryRef, void (*)(WiFiRef, CFTypeRef, void *, void *), void *);
    WiFiRef dev = WiFiDevice();
    if (!dev || !WiFiDeviceClientScanAsync_ || gScanCompletion) { if (completion && !gScanCompletion) completion(@[]); return; }
    gScanCompletion = [completion copy];
    WiFiDeviceClientScanAsync_(dev, (__bridge CFDictionaryRef)@{}, WiFiScanCallback, NULL);
    // Safety net: if the callback never fires, finish with an empty list after 8 s.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        void (^done)(NSArray *) = gScanCompletion;
        gScanCompletion = nil;
        if (done) done(@[]);
    });
}

static void WiFiAssocCallback(WiFiRef device, WiFiRef network, void *a, void *b, void *ctx) {
    NSLog(@"[LineageQS] wifi associate callback");
}

+ (BOOL)joinWiFi:(NSString *)ssid {
    WIFI_FN(CFArrayRef, WiFiManagerClientCopyNetworks, WiFiRef);
    WIFI_FN(void, WiFiDeviceClientAssociateAsync, WiFiRef, WiFiRef, void (*)(WiFiRef, WiFiRef, void *, void *, void *), void *);
    WiFiRef dev = WiFiDevice();
    CFArrayRef kn = (WiFiClient() && WiFiManagerClientCopyNetworks_) ? WiFiManagerClientCopyNetworks_(WiFiClient()) : NULL;
    BOOL started = NO;
    if (dev && WiFiDeviceClientAssociateAsync_ && kn && CFGetTypeID(kn) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(kn); i++) {
            WiFiRef net = CFArrayGetValueAtIndex(kn, i);
            if ([WiFiSSID(net) isEqualToString:ssid]) { WiFiDeviceClientAssociateAsync_(dev, net, WiFiAssocCallback, NULL); started = YES; break; }
        }
    }
    if (kn) CFRelease(kn);
    return started;
}

+ (void)disconnectWiFi {
    WIFI_FN(int, WiFiDeviceClientDisassociate, WiFiRef);
    WiFiRef dev = WiFiDevice();
    if (dev && WiFiDeviceClientDisassociate_) WiFiDeviceClientDisassociate_(dev);
}

static NSString *BTKind(id dev) {
    unsigned major = Has(dev, @"majorClass") ? ((unsigned (*)(id, SEL))objc_msgSend)(dev, NSSelectorFromString(@"majorClass")) : 0;
    // Bluetooth Core spec major device classes (bits 8-12 of CoD)
    switch (major) {
        case 0x400: return @"headphones"; // audio/video
        case 0x700: return @"watch";      // wearable
        case 0x200: return @"phone";
        case 0x100: return @"computer";
        default: return @"other";
    }
}

+ (NSArray<NSDictionary *> *)bluetoothDevices {
    id bt = Bluetooth();
    if (!Has(bt, @"pairedDevices")) return @[];
    NSArray *devs = ((id (*)(id, SEL))objc_msgSend)(bt, NSSelectorFromString(@"pairedDevices"));
    NSMutableArray *out = [NSMutableArray array];
    for (id d in ([devs isKindOfClass:NSArray.class] ? devs : @[])) {
        NSString *name = Has(d, @"name") ? ((id (*)(id, SEL))objc_msgSend)(d, NSSelectorFromString(@"name")) : nil;
        NSString *addr = Has(d, @"address") ? ((id (*)(id, SEL))objc_msgSend)(d, NSSelectorFromString(@"address")) : nil;
        if (![name isKindOfClass:NSString.class] || ![addr isKindOfClass:NSString.class]) continue;
        [out addObject:@{@"name": name, @"address": addr, @"connected": @(Has(d, @"connected") && GetBool(d, @"connected")),
                         @"battery": @(Has(d, @"batteryLevel") ? ((int (*)(id, SEL))objc_msgSend)(d, NSSelectorFromString(@"batteryLevel")) : -1),
                         @"kind": BTKind(d)}];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"connected"] boolValue] != [b[@"connected"] boolValue]) return [a[@"connected"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return out;
}

+ (BOOL)setBluetoothDevice:(NSString *)address connected:(BOOL)connected {
    id bt = Bluetooth();
    if (!Has(bt, @"deviceFromAddressString:")) return NO;
    id d = ((id (*)(id, SEL, id))objc_msgSend)(bt, NSSelectorFromString(@"deviceFromAddressString:"), address);
    NSString *sel = connected ? @"connect" : @"disconnect";
    if (!Has(d, sel)) return NO;
    Call0(d, sel);
    return YES;
}

+ (NSDictionary *)liveInfo {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return d;
    @try {
        id w = WiFi();
        if (Has(w, @"wiFiEnabled")) d[@"wifiOn"] = @(GetBool(w, @"wiFiEnabled"));
        if (Has(w, @"isAssociated")) d[@"wifiAssociated"] = @(GetBool(w, @"isAssociated"));
        if (Has(w, @"currentNetworkName")) { id n = ((id (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"currentNetworkName")); if ([n isKindOfClass:NSString.class]) d[@"wifiName"] = n; }
        if (Has(w, @"signalStrengthBars")) d[@"wifiBars"] = @(((int (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"signalStrengthBars")));

        // Real SIM (STTelephonySubscriptionInfo via SBTelephonyManager).
        id tm = Shared(@"SBTelephonyManager", @"sharedTelephonyManager");
        id sub = Has(tm, @"_primarySubscriptionInfo") ? ((id (*)(id, SEL))objc_msgSend)(tm, NSSelectorFromString(@"_primarySubscriptionInfo")) : nil;
        NSString *simStatus = [sub respondsToSelector:NSSelectorFromString(@"SIMStatus")] ? [sub valueForKey:@"SIMStatus"] : nil;
        BOOL noSIM = [simStatus isKindOfClass:NSString.class] && [simStatus containsString:@"NotInserted"];
        NSString *op = [sub respondsToSelector:NSSelectorFromString(@"operatorName")] ? [sub valueForKey:@"operatorName"] : nil;
        id bars = [sub respondsToSelector:NSSelectorFromString(@"signalStrengthBars")] ? [sub valueForKey:@"signalStrengthBars"] : nil;
        d[@"noSIM"] = @(noSIM);
        int cellData = CellularRead();
        if (cellData >= 0) d[@"cellDataOn"] = @(cellData == 1);
        if ([op isKindOfClass:NSString.class] && op.length) d[@"carrier"] = op;
        if ([bars respondsToSelector:@selector(integerValue)]) d[@"cellBars"] = @([bars integerValue]);
        id dct = [sub respondsToSelector:NSSelectorFromString(@"dataConnectionType")] ? [sub valueForKey:@"dataConnectionType"] : nil;
        NSString *dctS = [dct description].lowercaseString;
        NSDictionary *dm = @{@"lte": @"LTE", @"4g": @"4G", @"5g": @"5G", @"3g": @"3G", @"edge": @"E", @"gprs": @"G", @"umts": @"3G", @"hspa": @"H"};
        for (NSString *k in dm) if ([dctS containsString:k]) { d[@"network"] = dm[k]; break; } // assumption: mapping of the description text

        // FakeSIM (user's own tweak) replaces the status-bar carrier: mirror it so
        // the panel matches the status bar while it is installed and enabled.
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib/TweakInject/FakeSIM.dylib"]) {
            NSUserDefaults *fs = [[NSUserDefaults alloc] initWithSuiteName:@"com.makr.fakesim"];
            id en = [fs objectForKey:@"enabled"];
            if (!en || [en boolValue]) {
                d[@"fakeSIM"] = @YES;
                BOOL fsNoSIM = [[fs objectForKey:@"noSIM"] boolValue];
                d[@"noSIM"] = @(fsNoSIM);
                NSString *custom = [[fs stringForKey:@"customCarrier"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                NSString *carrier = custom.length ? custom : ([fs stringForKey:@"carrier"] ?: @"МТС");
                if (!fsNoSIM && ![[fs objectForKey:@"hideCarrier"] boolValue]) d[@"carrier"] = carrier;
                NSString *net = [fs stringForKey:@"network"] ?: @"LTE";
                if (![net isEqualToString:@"none"]) d[@"network"] = net;
                d[@"cellBars"] = @(fsNoSIM ? 0 : ([fs stringForKey:@"bars"] ?: @"4").integerValue);
            }
        }

        id bt = Bluetooth();
        if (Has(bt, @"connectedDevices")) {
            NSArray *devs = ((id (*)(id, SEL))objc_msgSend)(bt, NSSelectorFromString(@"connectedDevices"));
            id dev = [devs isKindOfClass:NSArray.class] ? devs.firstObject : nil;
            if (Has(dev, @"name")) {
                d[@"btDevice"] = ((id (*)(id, SEL))objc_msgSend)(dev, NSSelectorFromString(@"name")) ?: @"";
                d[@"btBattery"] = Has(dev, @"batteryLevel") ? @(((int (*)(id, SEL))objc_msgSend)(dev, NSSelectorFromString(@"batteryLevel"))) : @(-1);
            }
        }

        id f = Focus();
        id act = Has(f, @"activeActivity") ? ((id (*)(id, SEL))objc_msgSend)(f, NSSelectorFromString(@"activeActivity")) : nil;
        for (NSString *k in @[@"activityDisplayName", @"displayName", @"name"]) {
            if ([act respondsToSelector:NSSelectorFromString(k)]) { id n = [act valueForKey:k]; if ([n isKindOfClass:NSString.class]) { d[@"focusName"] = n; break; } }
        }
    } @catch (NSException *e) {
        NSLog(@"[LineageQS] liveInfo exception %@", e.reason);
    }
    return d;
}

+ (NSString *)secondaryLabelFor:(NSString *)ident info:(NSDictionary *)info {
    LQSBackendState st = [self stateFor:ident];
    if (st == LQSBackendStateUnavailable) return LQSL(@"Unavailable");       // qs_tile_state_unavailable
    if ([ident isEqualToString:@"wifi"]) {
        if (![info[@"wifiOn"] boolValue]) return LQSL(@"Off");                // state_off
        if ([info[@"wifiAssociated"] boolValue] && [info[@"wifiName"] length]) return info[@"wifiName"];
        return LQSL(@"Networks available");                                   // quick_settings_networks_available
    }
    if ([ident isEqualToString:@"cell"]) {
        if ([info[@"noSIM"] boolValue]) return LQSL(@"No SIM");               // keyguard_missing_sim_message_short
        if (st == LQSBackendStateOff) return LQSL(@"Off");
        NSString *c = info[@"carrier"], *n = info[@"network"];
        if (c.length && n.length) return [NSString stringWithFormat:@"%@, %@", c, n];
        return c.length ? c : (n ?: LQSL(@"On"));
    }
    if ([ident isEqualToString:@"bt"]) {
        if (st == LQSBackendStateOff) return LQSL(@"Off");
        NSString *dev = info[@"btDevice"];
        if (dev.length) {
            NSInteger b = [info[@"btBattery"] integerValue];
            return b > 0 ? [NSString stringWithFormat:@"%@ · %ld%% battery", dev, (long)b] : dev; // quick_settings_bluetooth_secondary_label_battery_level
        }
        return LQSL(@"On");
    }
    if ([ident isEqualToString:@"dnd"] && st == LQSBackendStateOn && [info[@"focusName"] length]) return info[@"focusName"];
    if ([ident isEqualToString:@"ringer"] && st >= 0) return st == LQSBackendStateOn ? LQSL(@"Ring") : LQSL(@"Mute"); // volume_ringer_status_*
    if (st == LQSBackendStateOn) return LQSL(@"On");
    if (st == LQSBackendStateOff) return LQSL(@"Off");
    return nil;
}

+ (NSString *)dumpClass:(NSString *)name {
    Class c = NSClassFromString(name);
    if (!c) return [NSString stringWithFormat:@"%@: MISSING", name];
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@ : %@\n", name, NSStringFromClass(class_getSuperclass(c))];
    for (int meta = 0; meta < 2; meta++) {
        unsigned n = 0;
        Method *ms = class_copyMethodList(meta ? object_getClass(c) : c, &n);
        for (unsigned i = 0; i < n; i++) [out appendFormat:@"%c %s %s\n", meta ? '+' : '-', sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i])];
        free(ms);
    }
    return out;
}

@end
