// Preview host: runs the Android 17 shade as an ordinary app (simulator or
// device) to check UI without touching SpringBoard. Launch arguments:
//   -state compact|expanded|editor   initial panel state
//   -demo 1                          enable demo tile states (host prefs only)
#import <UIKit/UIKit.h>
#import "LQSPanelViewController.h"
#import "LQSTheme.h"
#import "LQSVectorIcon.h"
#import "LQSModel.h"
#import "LQSStrings.h"
#import "LQSViews.h"

#import "LQSNotifications.h"
#import "LQSColorsViewController.h"

// Stand-in NCNotificationRequest for -demoNotifs (LQSNotificationItem reads these selectors).
@interface FakeContent : NSObject
@property (nonatomic, copy) NSString *header, *title, *message;
@property (nonatomic, strong) UIImage *icon;
@end
@implementation FakeContent
@end
@interface FakeRequest : NSObject
@property (nonatomic, copy) NSString *notificationIdentifier, *sectionIdentifier, *threadIdentifier;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) FakeContent *content;
@end
@implementation FakeRequest
@end

static void PostDemoNotifications(void) {
    NSArray *demo = @[@[@"org.telegram", @"Telegram", @"Гера", @"на Ваше «ага»"], @[@"org.telegram", @"Telegram", @"Гера", @"Стикер"],
                      @[@"org.telegram", @"Telegram", @"Мама", @"Позвони, как будешь свободен"], @[@"com.openai.chat", @"ChatGPT", @"ChatGPT", @"Преодоление прокрастинации. Конечно. Давай сначала разберёмся"],
                      @[@"com.discord", @"Discord", @"Shashwath", @"Can I pls have the springboard iOS 18 repo?"], @[@"com.discord", @"Discord", @"Shashwath", @"Sent a sticker: Wave"],
                      @[@"com.discord", @"Discord", @"RobTop", @"Update 2.2091 patch notes (bugfixes)"], @[@"com.twitter", @"X", @"Elon", @"Tweet tweet"],
                      @[@"com.apple.mail", @"Почта", @"GitHub", @"[repo] New issue opened"], @[@"com.apple.mail", @"Почта", @"Apple", @"Your receipt"]];
    NSInteger i = 0;
    for (NSArray *d in demo) {
        FakeContent *c = [FakeContent new];
        c.header = d[1]; c.title = d[2]; c.message = d[3];
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
        c.icon = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor colorWithHue:(([d[0] hash] % 360) / 360.0) saturation:0.6 brightness:0.8 alpha:1] setFill];
            UIRectFill(CGRectMake(0, 0, 40, 40));
        }];
        FakeRequest *q = [FakeRequest new];
        q.notificationIdentifier = [NSString stringWithFormat:@"demo-%ld", (long)i];
        q.sectionIdentifier = d[0];
        q.timestamp = [NSDate dateWithTimeIntervalSinceNow:-60.0 * (i * 7 + 2)];
        q.content = c;
        [[LQSNotifications shared] posted:q];
        i++;
    }
}

@interface HostVC : UIViewController <LQSPanelDelegate>
@end

@implementation HostVC {
    LQSPanelViewController *_panel;
    UIButton *_open;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Stand-in wallpaper so the scrim is visible.
    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[(id)[UIColor colorWithRed:0.25 green:0.3 blue:0.45 alpha:1].CGColor, (id)[UIColor colorWithRed:0.6 green:0.35 blue:0.3 alpha:1].CGColor];
    g.frame = self.view.bounds;
    [self.view.layer addSublayer:g];
    _open = [UIButton buttonWithType:UIButtonTypeSystem];
    [_open setTitle:@"Open panel" forState:UIControlStateNormal];
    _open.frame = CGRectMake(0, 600, self.view.bounds.size.width, 44);
    [_open addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_open];

    _panel = [LQSPanelViewController new];
    _panel.delegate = self;
    [self addChildViewController:_panel];
    _panel.view.frame = self.view.bounds;
    _panel.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_panel.view];
    [_panel didMoveToParentViewController:self];
    _panel.ownBackdrop = YES;

    if ([NSUserDefaults.standardUserDefaults boolForKey:@"notifs"]) PostDemoNotifications();
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"colors"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LQSColorsViewController *c = [LQSColorsViewController new];
            c.themePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"theme.json"];
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(375, 667)];
            c.wallpaper = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [[UIColor colorWithRed:0.1 green:0.35 blue:0.4 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, 375, 420));
                [[UIColor colorWithRed:0.85 green:0.5 blue:0.35 alpha:1] setFill]; UIRectFill(CGRectMake(0, 420, 375, 247));
            }];
            [self presentViewController:c animated:NO completion:nil];
        });
    }
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"icons"]) { [self showIconSheet]; return; }
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"animsheet"]) { [self showAnimSheet]; return; }
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"battery"]) { [self showBatterySheet]; return; }
    NSString *state = [NSUserDefaults.standardUserDefaults stringForKey:@"state"];
    if ([state isEqualToString:@"expanded"]) [_panel setState:LQSPanelStateExpanded animated:NO];
    if ([state isEqualToString:@"editor"]) [_panel setState:LQSPanelStateEditor animated:NO];
}
- (void)showIconSheet {
    // Contact sheet of every exported Android vector (template + coloured).
    _panel.view.hidden = YES;
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.backgroundColor = LQSNeutral1(900);
    [self.view addSubview:sv];
    NSString *dir = [LQSVectorIcon resourceDirectory];
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    CGFloat x = 4, y = 24, cw = 74;
    for (NSString *f in files) {
        if (![f hasSuffix:@".json"]) continue;
        NSString *name = [f stringByDeletingPathExtension];
        BOOL multi = [name hasPrefix:@"ic_qs_edit_resize"];
        UIImageView *iv = [[UIImageView alloc] initWithImage:multi ? [LQSVectorIcon coloredImageNamed:name side:28] : [LQSVectorIcon imageNamed:name side:28]];
        iv.tintColor = UIColor.whiteColor;
        iv.frame = CGRectMake(x + (cw - 28) / 2, y, 28, 28);
        [sv addSubview:iv];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x, y + 30, cw, 22)];
        l.text = name; l.numberOfLines = 2; l.font = [UIFont systemFontOfSize:7]; l.textColor = LQSNeutral1(400); l.textAlignment = NSTextAlignmentCenter;
        [sv addSubview:l];
        x += cw;
        if (x + cw > self.view.bounds.size.width) { x = 4; y += 58; }
    }
    sv.contentSize = CGSizeMake(self.view.bounds.size.width, y + 70);
}

- (void)showBatterySheet {
    // Android 17 unified battery, 4x scale, dark and light backgrounds.
    _panel.view.hidden = YES;
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    UIView *dark = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H / 2)];
    dark.backgroundColor = UIColor.blackColor;
    UIView *light = [[UIView alloc] initWithFrame:CGRectMake(0, H / 2, W, H / 2)];
    light.backgroundColor = UIColor.whiteColor;
    [self.view addSubview:dark]; [self.view addSubview:light];
    NSArray *states = @[@[@100, @NO, @NO, @NO, @"100"], @[@57, @NO, @NO, @YES, @"57 %"], @[@15, @NO, @NO, @NO, @"15"], @[@80, @YES, @NO, @YES, @"80 chg"], @[@60, @NO, @YES, @YES, @"60 saver"], @[@4, @NO, @NO, @YES, @"4 crit"]];
    for (int pass = 0; pass < 2; pass++) {
        UIView *host = pass ? light : dark;
        for (NSUInteger i = 0; i < states.count; i++) {
            NSArray *st = states[i];
            LQSBatteryView *b = [LQSBatteryView new];
            b.level = [st[0] integerValue]; b.charging = [st[1] boolValue]; b.powerSave = [st[2] boolValue]; b.showPercent = [st[3] boolValue];
            b.darkBackground = !pass;
            CGSize sz = [b sizeThatFits:CGSizeMake(0, 52)];
            CGFloat x = 16 + (i % 3) * 120, y = 40 + (i / 3) * 110;
            b.frame = CGRectMake(x, y, sz.width, sz.height);
            [host addSubview:b];
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x, y + 60, 110, 16)];
            l.text = st[4]; l.font = [UIFont systemFontOfSize:11]; l.textColor = pass ? UIColor.darkGrayColor : UIColor.lightGrayColor;
            [host addSubview:l];
        }
    }
}

- (void)showAnimSheet {
    // 8 frames (t = 0 ... duration) of every animated vector, one row each.
    _panel.view.hidden = YES;
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.backgroundColor = LQSNeutral1(900);
    [self.view addSubview:sv];
    NSInteger page = [NSUserDefaults.standardUserDefaults integerForKey:@"animpage"];
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[LQSVectorIcon resourceDirectory] error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *animated = [NSMutableArray array];
    for (NSString *f in files) if ([f hasSuffix:@".json"] && [LQSVectorIcon animationDurationNamed:[f stringByDeletingPathExtension]] > 0) [animated addObject:[f stringByDeletingPathExtension]];
    CGFloat y = 24;
    for (NSUInteger i = page * 12; i < MIN(animated.count, (page + 1) * 12); i++) {
        NSString *name = animated[i];
        NSTimeInterval d = [LQSVectorIcon animationDurationNamed:name];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(4, y, 370, 10)];
        l.text = [NSString stringWithFormat:@"%@  %.0f ms", name, d * 1000]; l.font = [UIFont systemFontOfSize:8]; l.textColor = LQSNeutral1(400);
        [sv addSubview:l];
        for (int k = 0; k < 8; k++) {
            UIImageView *iv = [[UIImageView alloc] initWithImage:[LQSVectorIcon frameNamed:name side:34 atTime:d * k / 7.0]];
            iv.tintColor = UIColor.whiteColor;
            iv.frame = CGRectMake(6 + k * 46, y + 11, 34, 34);
            [sv addSubview:iv];
        }
        y += 50;
    }
    sv.contentSize = CGSizeMake(self.view.bounds.size.width, y + 20);
}

- (void)openPanel {
    _panel.view.hidden = NO;
    [_panel setPresentationProgress:0];
    [_panel setPresentationProgress:1 interactive:NO];
}
- (void)panelRequestsDismiss:(LQSPanelViewController *)panel {
    [panel setPresentationProgress:0 interactive:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ panel.view.hidden = YES; });
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

@interface HostDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HostDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    NSString *res = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"LineageQS"];
    [LQSTheme setResourceRoot:res];
    [LQSVectorIcon setResourceDirectory:[res stringByAppendingPathComponent:@"vectors"]];
    LQSStringsSetDirectory([res stringByAppendingPathComponent:@"strings"]);
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"demo"]) {
        CFPreferencesSetAppValue(CFSTR("demoStates"), kCFBooleanTrue, (__bridge CFStringRef)LQSPrefsDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)LQSPrefsDomain);
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HostVC new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HostDelegate.class)); }
}
