// LineageQS — Android 17 (LineageOS 24) shade inside the native iOS 16
// Control Center (iPhone 8, Dopamine rootless).
//
// Integration (verified path, device-probe-v2/cc-path-session-2026-10-16.log):
// bottom SBScreenEdgePanGestureRecognizer -> SBControlCenterController grabber
// callbacks -> CCUIModularControlCenterOverlayViewController begin/update/end
// presentation -> _updatePresentationForTransitionState: (interactive progress)
// -> _didPresent. We keep SBControlCenterController, SBControlCenterWindow, the
// overlay VC, its presenter and all gestures. We only add LQSPanelViewController
// as a child of the overlay VC and hide its module scroll view / header pocket.
// Removing the child and un-hiding those views restores stock Control Center.
//
// Safety: kill switch file, crash-loop guard, master switch default off,
// every install step in @try. No tile or slider talks to iOS services.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import "Sources/LQSPanelViewController.h"
#import "Sources/LQSModel.h"
#import "Sources/LQSTheme.h"
#import "Sources/LQSVectorIcon.h"
#import "Sources/LQSBackends.h"
#import "Sources/LQSNotifications.h"
#import "Sources/LQSStrings.h"

@interface CCUIModularControlCenterOverlayViewController : UIViewController
- (void)beginPresentationWithLocation:(CGPoint)l translation:(CGPoint)t velocity:(CGPoint)v;
- (void)updatePresentationWithLocation:(CGPoint)l translation:(CGPoint)t velocity:(CGPoint)v;
- (void)endPresentationWithLocation:(CGPoint)l translation:(CGPoint)t velocity:(CGPoint)v;
- (void)cancelPresentationWithLocation:(CGPoint)l translation:(CGPoint)t velocity:(CGPoint)v;
@end
@interface SBGrabberTongue : NSObject
@end
@interface SBCoverSheetSlidingViewController : UIViewController
@end
@interface SBControlCenterController : NSObject
+ (instancetype)sharedInstanceIfExists;
- (void)dismissAnimated:(BOOL)animated;
- (void)presentAnimated:(BOOL)animated;
- (BOOL)isPresented;
- (UIWindow *)window;
- (id)grabberTongue;
- (id)viewController;
- (void)_handleStatusBarPullDownGesture:(id)g;
@end

static NSString *const kLogPath = @"/var/mobile/Library/LineageQS/lineageqs.log";
static NSString *const kBootCountPath = @"/var/mobile/Library/LineageQS/boot-count";
static NSString *const kDebugFlagPath = @"/var/mobile/Library/LineageQS/DEBUG";

static BOOL gEnabled;           // master switch (live)
static BOOL gDisabledHard;      // kill switch / crash guard / exception
static __weak CCUIModularControlCenterOverlayViewController *gOverlay;
static LQSPanelViewController *gPanel;

static void NLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ [%d] %@\n", [NSDate date], getpid(), msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:kLogPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static NSString *ResourceRoot(void) {
    for (NSString *p in @[@"/var/jb/Library/Application Support/LineageQS", @"/Library/Application Support/LineageQS"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

static void HardDisable(NSString *reason) {
    gDisabledHard = YES;
    [@"" writeToFile:LQSKillSwitchPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NLog(@"HARD DISABLE: %@ (created %@)", reason, LQSKillSwitchPath);
}

static id IvarValue(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

// Native views replaced by the panel. Their own alpha animations keep
// running; we only force hidden while our panel is installed.
static void SetNativeContentHidden(UIViewController *overlay, BOOL hidden) {
    static const char *names[] = {"_scrollView", "_headerPocketView", "_compactLeadingStatusBar"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        UIView *v = IvarValue(overlay, names[i]);
        if ([v isKindOfClass:UIView.class] && v.hidden != hidden) v.hidden = hidden;
    }
}

@interface LQSDismissProxy : NSObject <LQSPanelDelegate>
@end
@implementation LQSDismissProxy
- (void)panelRequestsDismiss:(LQSPanelViewController *)panel {
    // Native path: SBControlCenterController runs _willDismiss/_didDismiss,
    // releases its assertions and hides SBControlCenterWindow.
    SBControlCenterController *cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
    NLog(@"panel requests dismiss (cc=%p presented=%d)", cc, cc ? [cc isPresented] : -1);
    [cc dismissAnimated:YES];
}
@end
static LQSDismissProxy *gProxy;

static void Uninstall(NSString *why) {
    CCUIModularControlCenterOverlayViewController *ov = gOverlay;
    if (gPanel) {
        @try {
            [gPanel willMoveToParentViewController:nil];
            [gPanel.view removeFromSuperview];
            [gPanel removeFromParentViewController];
        } @catch (NSException *e) {
            NLog(@"uninstall exception %@", e);
        }
        gPanel = nil;
        NLog(@"panel removed (%@)", why);
    }
    if (ov) SetNativeContentHidden(ov, NO);
}

static void Install(CCUIModularControlCenterOverlayViewController *ov) {
    if (!ov || gPanel || !gEnabled || gDisabledHard || !ov.isViewLoaded) return;
    @try {
        NSString *root = ResourceRoot();
        if (!root) { NLog(@"resources missing, not installing"); return; }
        [LQSTheme setResourceRoot:root];
        [LQSVectorIcon setResourceDirectory:[root stringByAppendingPathComponent:@"vectors"]];
        LQSStringsSetDirectory([root stringByAppendingPathComponent:@"strings"]); // Android translations, phone language
        if (!gProxy) gProxy = [LQSDismissProxy new];
        LQSPanelViewController *panel = [LQSPanelViewController new];
        panel.delegate = gProxy;
        [ov addChildViewController:panel];
        panel.view.frame = ov.view.bounds;
        panel.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [ov.view addSubview:panel.view];
        [panel didMoveToParentViewController:ov];
        gPanel = panel;
        SetNativeContentHidden(ov, YES);
        // Closed state until the native transition reports progress.
        SBControlCenterController *cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
        [panel setPresentationProgress:(cc && [cc isPresented]) ? 1 : 0];
        NLog(@"panel installed into %@ %@", NSStringFromClass(ov.class), NSStringFromCGRect(ov.view.bounds));
    } @catch (NSException *e) {
        HardDisable([NSString stringWithFormat:@"install exception %@", e]);
        Uninstall(@"exception");
    }
}

static CCUIModularControlCenterOverlayViewController *CurrentOverlay(void) {
    if (gOverlay) return gOverlay;
    id cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
    id vc = [cc respondsToSelector:@selector(viewController)] ? [cc performSelector:@selector(viewController)] : nil;
    if ([vc isKindOfClass:objc_getClass("CCUIModularControlCenterOverlayViewController")]) gOverlay = vc;
    return gOverlay;
}

static void ReloadGesturePrefs(void);

static void ReloadPrefs(void) {
    BOOL kill = [[NSFileManager defaultManager] fileExistsAtPath:LQSKillSwitchPath];
    if (kill) gDisabledHard = YES;
    gEnabled = [LQSSettings current].enabled && !gDisabledHard;
    NLog(@"prefs: enabled=%d hardDisabled=%d", gEnabled, gDisabledHard);
    ReloadGesturePrefs();
    if (gEnabled) {
        Install(CurrentOverlay());
        [gPanel reloadFromPreferences];
    } else {
        Uninstall(@"master off or kill switch");
    }
}

%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLoad {
    %orig;
    gOverlay = self;
    Install(self);
}

- (void)viewWillLayoutSubviews {
    %orig;
    if (gOverlay != self) gOverlay = self;
    if (gPanel && gPanel.parentViewController == self) {
        SetNativeContentHidden(self, YES);
        gPanel.view.frame = self.view.bounds;
        [self.view bringSubviewToFront:gPanel.view];
    }
}

- (void)_updatePresentationForTransitionState:(id)state withCompletionHander:(id)handler {
    // Install lazily if viewDidLoad ran before this dylib was loaded. Before
    // %orig so the first transition frame already shows the panel.
    if (!gPanel && gEnabled && !gDisabledHard) { gOverlay = self; Install(self); }
    %orig;
    if (gPanel && gPanel.parentViewController == self) {
        @try {
            SetNativeContentHidden(self, YES);
            double p = [[state valueForKey:@"presentationProgress"] doubleValue];
            [gPanel setPresentationProgress:p interactive:[[state valueForKey:@"interactive"] boolValue]];
            // Log threshold crossings only (start, half, fully presented, fully dismissed).
            static int lastBucket = -1;
            int bucket = p <= 0.001 ? 0 : p < 0.5 ? 1 : p < 0.999 ? 2 : 3;
            if (bucket != lastBucket) {
                NLog(@"transition type=%@ interactive=%@ presentationProgress=%.3f", [state valueForKey:@"type"], [state valueForKey:@"interactive"], p);
                lastBucket = bucket;
            }
        } @catch (NSException *e) {
            HardDisable([NSString stringWithFormat:@"progress exception %@", e]);
            Uninstall(@"exception");
        }
    }
}

// Native dismissal tap/pan/flick recognizers use the overlay VC as delegate.
// Touches that land on our panel content belong to the panel.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (gPanel && gPanel.parentViewController == self && [touch.view isDescendantOfView:gPanel.view]) return NO;
    return %orig;
}

%end


#pragma mark - Live status updates

// Event-driven status data (confirmed by the first device probe: callbacks with
// action masks on Wi-Fi / cellular / time changes). Forward as a local
// notification; the panel coalesces and only refreshes while visible.
%hook SBMainStatusBarStateProvider
- (void)statusBarStateProvider:(id)provider didPostStatusBarData:(const void *)data withActions:(int)actions {
    %orig;
    if (gPanel) [[NSNotificationCenter defaultCenter] postNotificationName:LQSLiveInfoChangedNotification object:nil];
}
%end

#pragma mark - Notifications mirror

// NCNotificationDispatcher post/modify/withdraw (signatures dumped on device:
// v24@0:8@16). %orig first; the mirror only reads the request.
%hook NCNotificationDispatcher
- (void)postNotificationWithRequest:(id)request {
    %orig;
    @try { [LQSNotifications shared].dispatcher = self; [[LQSNotifications shared] posted:request]; NLog(@"notif post %@", [request valueForKey:@"sectionIdentifier"]); } @catch (NSException *e) { NLog(@"notif post exception %@", e.reason); }
}
- (void)modifyNotificationWithRequest:(id)request {
    %orig;
    @try { [LQSNotifications shared].dispatcher = self; [[LQSNotifications shared] modified:request]; } @catch (NSException *e) { NLog(@"notif modify exception %@", e.reason); }
}
- (void)withdrawNotificationWithRequest:(id)request {
    %orig;
    @try { [[LQSNotifications shared] withdrawn:request]; NLog(@"notif withdraw %@", [request valueForKey:@"sectionIdentifier"]); } @catch (NSException *e) { NLog(@"notif withdraw exception %@", e.reason); }
}
%end

#pragma mark - Gestures

// Settings: bottomSwipe (default YES = stock), topSwipe (default NO),
// topSwipeSplit (NO: whole top edge opens the panel; YES: Android dual-shade
// split, left half keeps Notification Center, config_invocationGestureSplitRatio
// 0.5), topRoute (0 presentAnimated, 1 interactive via overlay VC,
// 2 _handleStatusBarPullDownGesture:). Read live from preferences.
static id PrefObj(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)LQSPrefsDomain));
}
static BOOL PrefB(NSString *key, BOOL def) { id v = PrefObj(key); return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def; }
static NSInteger PrefI(NSString *key, NSInteger def) { id v = PrefObj(key); return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def; }

static BOOL gBottomSwipe = YES, gTopSwipe = NO, gTopSplit = NO;
static NSInteger gTopRoute = 0;

static void ReloadGesturePrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
    BOOL active = gEnabled && !gDisabledHard; // gestures only change while the panel is enabled
    gBottomSwipe = !active || PrefB(@"bottomSwipe", YES);
    gTopSwipe = active && PrefB(@"topSwipe", NO);
    gTopSplit = PrefB(@"topSwipeSplit", NO);
    gTopRoute = PrefI(@"topRoute", 1); // default: interactive, follows the finger
    NLog(@"gestures: bottomSwipe=%d topSwipe=%d split=%d route=%ld", gBottomSwipe, gTopSwipe, gTopSplit, (long)gTopRoute);
}

static __weak UIGestureRecognizer *gRoutedGesture;

static void MirrorForOverlay(UIPanGestureRecognizer *g, CGPoint *loc, CGPoint *tr, CGPoint *vel) {
    // The iPhone 8 overlay presenter (slide-up) opens on upward translation.
    // A downward pull from the top edge is mirrored so progress follows the finger.
    UIView *v = g.view;
    CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
    CGPoint l = [g locationInView:v], t = [g translationInView:v], ve = [g velocityInView:v];
    // Landscape: the gesture view stays in portrait coordinates, so "down on screen" runs
    // along X. Which way depends on the side the pull started from (top edge of the screen).
    static UIInterfaceOrientation o;
    if (g.state == UIGestureRecognizerStateBegan || o == UIInterfaceOrientationUnknown) {
        UIApplication *app = UIApplication.sharedApplication;
        o = [app respondsToSelector:@selector(activeInterfaceOrientation)] ? ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(app, @selector(activeInterfaceOrientation)) : UIInterfaceOrientationPortrait;
    }
    CGPoint start = CGPointMake(l.x - t.x, l.y - t.y);
    if (UIInterfaceOrientationIsLandscape(o) && start.y > 60 && (start.x < 60 || start.x > w - 60)) {
        CGFloat sign = start.x < w / 2 ? 1 : -1, down = sign * t.x, vdown = sign * ve.x, along = start.x < w / 2 ? l.y : h - l.y;
        *loc = CGPointMake(along, h - down);
        *tr = CGPointMake(0, -down);
        *vel = CGPointMake(0, -vdown);
        return;
    }
    *loc = CGPointMake(l.x, h - l.y);
    *tr = CGPointMake(t.x, -t.y);
    *vel = CGPointMake(ve.x, -ve.y);
}

static BOOL RouteTopGesture(UIPanGestureRecognizer *g) {
    SBControlCenterController *cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
    CCUIModularControlCenterOverlayViewController *ov = CurrentOverlay();
    UIGestureRecognizerState st = g.state;
    CGPoint loc, tr, vel;
    MirrorForOverlay(g, &loc, &tr, &vel);
    static CFAbsoluteTime lastLog;
    if (st != UIGestureRecognizerStateChanged || CFAbsoluteTimeGetCurrent() - lastLog > 0.15) {
        lastLog = CFAbsoluteTimeGetCurrent();
        NLog(@"TOP state=%ld route=%ld raw=(%.0f,%.0f) t=(%.0f,%.0f) presented=%d", (long)st, (long)gTopRoute,
             [g locationInView:g.view].x, [g locationInView:g.view].y, tr.x, -tr.y, [cc isPresented]);
    }
    @try {
        switch (gTopRoute) {
            case 1:
                if (!ov) return NO;
                if (st == UIGestureRecognizerStateBegan) [ov beginPresentationWithLocation:loc translation:tr velocity:vel];
                else if (st == UIGestureRecognizerStateChanged) [ov updatePresentationWithLocation:loc translation:tr velocity:vel];
                else if (st == UIGestureRecognizerStateEnded) [ov endPresentationWithLocation:loc translation:tr velocity:vel];
                else [ov cancelPresentationWithLocation:loc translation:tr velocity:vel];
                break;
            case 2:
                [cc _handleStatusBarPullDownGesture:g];
                break;
            default:
                if (st == UIGestureRecognizerStateBegan && ![cc isPresented]) [cc presentAnimated:YES];
                break;
        }
    } @catch (NSException *e) {
        NLog(@"TOP route exception %@ -> topSwipe off", e);
        gTopSwipe = NO;
        return NO;
    }
    return YES;
}

%hook SBGrabberTongue
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    BOOL r = %orig;
    if (r && !gBottomSwipe) {
        SBControlCenterController *cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
        if (cc && [cc grabberTongue] == (id)self) {
            NLog(@"bottom CC grabber blocked");
            return NO;
        }
    }
    return r;
}
%end


%hook SBCoverSheetSlidingViewController
- (void)_handlePresentGesture:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        gRoutedGesture = nil;
        CGPoint p = [g locationInView:g.view];
        BOOL leftHalf = p.x < g.view.bounds.size.width * 0.5; // config_invocationGestureSplitRatio
        NLog(@"cover sheet present gesture began in %@ at (%.0f,%.0f) topSwipe=%d split=%d left=%d", NSStringFromClass(self.class), p.x, p.y, gTopSwipe, gTopSplit, leftHalf);
        // Android dual shade: left half = notifications shade (ours when notifShade=YES,
        // otherwise iOS Notification Center), right half (or no split) = quick settings.
        BOOL ownNotifs = PrefB(@"notifShade", YES);
        if (gTopSwipe && [g isKindOfClass:UIPanGestureRecognizer.class] && !(gTopSplit && leftHalf && !ownNotifs)) {
            gRoutedGesture = g;
            gPanel.notificationsMode = gTopSplit && leftHalf;
        }
    }
    if (gRoutedGesture && gRoutedGesture == g) {
        if (!RouteTopGesture(g)) {
            gRoutedGesture = nil;
            %orig;
            return;
        }
        if (g.state >= UIGestureRecognizerStateEnded) gRoutedGesture = nil;
        return; // cover sheet is not moved for a routed gesture
    }
    %orig;
}
%end

static void DebugCommand(NSString *cmd) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kDebugFlagPath]) { NLog(@"debug %@ ignored (no DEBUG flag)", cmd); return; }
    SBControlCenterController *cc = [objc_getClass("SBControlCenterController") sharedInstanceIfExists];
    NLog(@"debug %@ (presented=%d)", cmd, [cc isPresented]);
    if ([cmd isEqualToString:@"present"]) [cc presentAnimated:YES];
    else if ([cmd isEqualToString:@"dismiss"]) [cc dismissAnimated:YES];
    else if ([cmd isEqualToString:@"expanded"]) [gPanel setState:LQSPanelStateExpanded animated:YES];
    else if ([cmd isEqualToString:@"compact"]) [gPanel setState:LQSPanelStateCompact animated:YES];
    else if ([cmd isEqualToString:@"editor"]) [gPanel setState:LQSPanelStateEditor animated:YES];
    else if ([cmd isEqualToString:@"dialogwifi"]) [gPanel showDetailsFor:@"wifi"];
    else if ([cmd isEqualToString:@"dialogbt"]) [gPanel showDetailsFor:@"bt"];
    else if ([cmd isEqualToString:@"notifs"]) { gPanel.notificationsMode = YES; [cc presentAnimated:YES]; }
    else if ([cmd isEqualToString:@"gestures"]) {
        // Every recognizer from the notification list up to the window (who can steal the scroll).
        UIView *v = [gPanel valueForKey:@"debugListView"];
        NSMutableString *out = [NSMutableString string];
        for (; v; v = v.superview) {
            for (UIGestureRecognizer *r in v.gestureRecognizers)
                [out appendFormat:@"%@ <- %@ enabled=%d state=%ld delegate=%@ cancels=%d\n", NSStringFromClass(v.class), NSStringFromClass(r.class), r.enabled, (long)r.state,
                                  r.delegate ? NSStringFromClass([(NSObject *)r.delegate class]) : @"-", r.cancelsTouchesInView];
        }
        UIScrollView *sv = (UIScrollView *)[gPanel valueForKey:@"debugListView"];
        [out appendFormat:@"list frame=%@ inWindow=%@ content=%@ offset=%@ inset=%@ scrollEnabled=%d ui=%d superUI=%d hidden=%d alpha=%.2f\n", NSStringFromCGRect(sv.frame),
                          NSStringFromCGRect([sv convertRect:sv.bounds toView:nil]), NSStringFromCGSize(sv.contentSize), NSStringFromCGPoint(sv.contentOffset),
                          NSStringFromUIEdgeInsets(sv.adjustedContentInset), sv.scrollEnabled, sv.userInteractionEnabled, sv.superview.userInteractionEnabled, sv.superview.hidden, sv.superview.alpha];
        CGPoint mid = CGPointMake(CGRectGetMidX([sv convertRect:sv.bounds toView:nil]), CGRectGetMidY([sv convertRect:sv.bounds toView:nil]));
        UIView *hit = [sv.window hitTest:mid withEvent:nil];
        [out appendFormat:@"hitTest(%@) -> %@ in %@\n", NSStringFromCGPoint(mid), NSStringFromClass(hit.class), NSStringFromClass(hit.superview.class)];
        NLog(@"gestures:\n%@", out);
    }
    else if ([cmd isEqualToString:@"qs"]) gPanel.notificationsMode = NO;
    else if ([cmd isEqualToString:@"backend"]) {
        // Reads <state>/cmd: "dump <Class>" | "state <tile>" | "set <tile> 0|1" | "brightness <0..1>"
        NSString *line = [[NSString stringWithContentsOfFile:@"/var/mobile/Library/LineageQS/cmd" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray *a = [line componentsSeparatedByString:@" "];
        NSString *out = @"?";
        if (a.count >= 2 && [a[0] isEqualToString:@"dump"]) out = [LQSBackends dumpClass:a[1]];
        else if (a.count >= 2 && [a[0] isEqualToString:@"state"]) out = [NSString stringWithFormat:@"state %@ = %ld", a[1], (long)[LQSBackends stateFor:a[1]]];
        else if (a.count >= 3 && [a[0] isEqualToString:@"set"]) {
            BOOL ok = [LQSBackends setOn:[a[2] boolValue] forIdentifier:a[1]];
            out = [NSString stringWithFormat:@"set %@ %@ ok=%d readback=%ld", a[1], a[2], ok, (long)[LQSBackends stateFor:a[1]]];
        } else if (a.count >= 3 && [a[0] isEqualToString:@"chain"]) {
            // chain <Class> <sel> [<sel> ...]: object-returning, no-argument selectors only.
            id obj = NSClassFromString(a[1]);
            NSMutableString *m = [NSMutableString string];
            for (NSUInteger i = 2; i < a.count && obj; i++) {
                SEL sel = NSSelectorFromString(a[i]);
                if (![obj respondsToSelector:sel]) { [m appendFormat:@"%@: no %@\n", NSStringFromClass([obj class]), a[i]]; obj = nil; break; }
                Method meth = [obj isKindOfClass:object_getClass(obj)] ? class_getInstanceMethod([obj class], sel) : class_getClassMethod(obj, sel);
                const char *ret = meth ? method_copyReturnType(meth) : strdup("@");
                if (ret[0] == '@') obj = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
                else { [m appendFormat:@"%@ -> non-object return %s = %lld\n", a[i], ret, ((long long (*)(id, SEL))objc_msgSend)(obj, sel)]; obj = nil; }
                free((void *)ret);
                if (obj) [m appendFormat:@"%@ -> %@ %@\n", a[i], NSStringFromClass([obj class]), [[obj description] substringToIndex:MIN((NSUInteger)400, [obj description].length)]];
            }
            out = m;
        } else if ([a[0] isEqualToString:@"wifiscan"]) {
            [LQSBackends scanWiFiWithCompletion:^(NSArray *nets) {
                NSString *r = [NSString stringWithFormat:@"%lu networks\n%@", (unsigned long)nets.count, nets];
                [r writeToFile:@"/var/mobile/Library/LineageQS/cmd.out" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                NLog(@"wifiscan -> %lu", (unsigned long)nets.count);
            }];
            return; // answer is written asynchronously
        } else if ([a[0] isEqualToString:@"notifs"]) {
            out = [[LQSNotifications shared] debugListing];
        } else if ([a[0] isEqualToString:@"btlist"]) {
            out = [[LQSBackends bluetoothDevices] description];
        } else if (a.count >= 3 && [a[0] isEqualToString:@"dlsym"]) {
            void *h = dlopen([a[1] UTF8String], RTLD_LAZY);
            NSMutableString *m = [NSMutableString stringWithFormat:@"%@ handle=%p\n", a[1], h];
            for (NSUInteger i = 2; i < a.count; i++) [m appendFormat:@"%@ %@\n", dlsym(h ?: RTLD_DEFAULT, [a[i] UTF8String]) ? @"YES" : @"NO ", a[i]];
            out = m;
        } else if (a.count >= 2 && [a[0] isEqualToString:@"load"]) {
            out = [NSString stringWithFormat:@"dlopen %@ -> %p", a[1], dlopen([a[1] UTF8String], RTLD_LAZY)];
        } else if (a.count >= 2 && [a[0] isEqualToString:@"open"]) {
            out = [NSString stringWithFormat:@"open %@ %@ -> %d", a[1], [LQSBackends settingsURLFor:a[1]], [LQSBackends openSettingsFor:a[1]]];
        } else if (a.count >= 2 && [a[0] isEqualToString:@"brightness"]) {
            [LQSBackends setBrightness:[a[1] doubleValue]];
            out = [NSString stringWithFormat:@"brightness readback=%.3f", [LQSBackends brightness]];
        }
        [out writeToFile:@"/var/mobile/Library/LineageQS/cmd.out" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NLog(@"backend cmd '%@' -> %@", line, out.length > 300 ? [out substringToIndex:300] : out);
    }
    else if ([cmd isEqualToString:@"screen"]) {
        // Whole screen incl. the system status bar window (UIKit private _UICreateScreenUIImage).
        UIImage *(*shot)(void) = (UIImage *(*)(void))dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
        UIImage *img = shot ? shot() : nil;
        [UIImagePNGRepresentation(img) writeToFile:@"/var/mobile/Library/LineageQS/screen.png" atomically:YES];
        NLog(@"screen written %d", img != nil);
    }
    else if ([cmd isEqualToString:@"snapshot"]) {
        UIWindow *w = [cc window];
        if (!w) return;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:w.bounds];
        UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO]; }];
        [UIImagePNGRepresentation(img) writeToFile:@"/var/mobile/Library/LineageQS/snapshot.png" atomically:YES];
        NLog(@"snapshot written hidden=%d", w.hidden);
    }
}

static void RegisterDarwin(NSString *name, void (^block)(void)) {
    int token;
    notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int t) { block(); });
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:LQSStateDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        if ([[NSFileManager defaultManager] fileExistsAtPath:LQSKillSwitchPath]) {
            NLog(@"kill switch present: hooks NOT installed. Remove %@ and respring to re-arm.", LQSKillSwitchPath);
            return;
        }
        // Crash-loop guard: SpringBoard starts that never reach the 90 s
        // "stable" mark are counted. sbreload on this device starts SpringBoard
        // twice per respring (journal 2026-10-16), so the limit is 6 starts
        // (= about three failed resprings), not 3.
        NSInteger boots = [[NSString stringWithContentsOfFile:kBootCountPath encoding:NSUTF8StringEncoding error:nil] integerValue];
        if (boots >= 6) {
            [@"0" writeToFile:kBootCountPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            HardDisable(@"crash-loop guard (6 unstable SpringBoard starts)");
            return;
        }
        [[NSString stringWithFormat:@"%ld", (long)boots + 1] writeToFile:kBootCountPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [@"0" writeToFile:kBootCountPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NLog(@"stable mark (boot counter reset)");
        });

        gEnabled = [LQSSettings current].enabled;
        NLog(@"loaded: enabled=%d iOS=%@", gEnabled, UIDevice.currentDevice.systemVersion);
        %init;
        ReloadGesturePrefs();

        RegisterDarwin(LQSPrefsChangedNotification, ^{ ReloadPrefs(); });
        for (NSString *n in @[@"com.apple.springboard.ringerstate", @"com.apple.system.lowpowermode", @"com.apple.system.config.network_change"]) {
            RegisterDarwin(n, ^{ if (gPanel) [[NSNotificationCenter defaultCenter] postNotificationName:LQSLiveInfoChangedNotification object:nil]; });
        }
        // Material You theme applied in Settings > LineageQS > Colors: reload and rebuild the panel
        // (colours are resolved when views are created).
        RegisterDarwin(@"com.makr.materialyou/theme-changed", ^{
            [LQSTheme reloadTheme];
            if (gPanel) { Uninstall(@"theme changed"); Install(CurrentOverlay()); }
            NLog(@"theme reloaded");
        });
        RegisterDarwin(LQSLayoutResetNotification, ^{
            [[LQSModel shared] resetLayout];
            [gPanel reloadFromPreferences];
            NLog(@"layout reset");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (gEnabled) Install(CurrentOverlay()); });
        for (NSString *cmd in @[@"present", @"dismiss", @"expanded", @"compact", @"editor", @"snapshot", @"backend", @"dialogwifi", @"dialogbt", @"notifs", @"qs", @"screen", @"gestures"]) {
            RegisterDarwin([@"com.makr.lineageqs/debug-" stringByAppendingString:cmd], ^{ DebugCommand(cmd); });
        }
    }
}
