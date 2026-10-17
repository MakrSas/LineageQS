// lqsctl — command line control for LineageQS (run as root or mobile over SSH).
//   lqsctl disable   create kill switch + switch master off; panel removed live
//   lqsctl enable    remove kill switch, master on (SpringBoard applies live if hooks loaded)
//   lqsctl off       master off only
//   lqsctl status    print state
//   lqsctl reset     reset tile layout
//   lqsctl set <key> <bool|int>   e.g. set topSwipe 1, set bottomSwipe 0, set topRoute 1
//   lqsctl debug-<present|dismiss|expanded|compact|editor|snapshot>   needs DEBUG flag file
#import <Foundation/Foundation.h>
#import <notify.h>

static NSString *const kDomain = @"com.makr.lineageqs";
static NSString *const kDir = @"/var/mobile/Library/LineageQS";

static void SetEnabled(BOOL on) {
    CFPreferencesSetValue(CFSTR("enabled"), on ? kCFBooleanTrue : kCFBooleanFalse, (__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? @(argv[1]) : @"status";
        NSString *kill = [kDir stringByAppendingPathComponent:@"DISABLE"];
        NSFileManager *fm = NSFileManager.defaultManager;
        if ([cmd isEqualToString:@"disable"]) {
            [fm createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
            [@"" writeToFile:kill atomically:YES encoding:NSUTF8StringEncoding error:nil];
            SetEnabled(NO);
            notify_post("com.makr.lineageqs/prefs-changed");
            printf("kill switch created, master off\n");
        } else if ([cmd isEqualToString:@"enable"]) {
            [fm removeItemAtPath:kill error:nil];
            SetEnabled(YES);
            notify_post("com.makr.lineageqs/prefs-changed");
            printf("kill switch removed, master on (if hooks are not loaded: respring)\n");
        } else if ([cmd isEqualToString:@"off"]) {
            SetEnabled(NO);
            notify_post("com.makr.lineageqs/prefs-changed");
            printf("master off\n");
        } else if ([cmd isEqualToString:@"set"] && argc > 3) {
            NSString *key = @(argv[2]);
            NSInteger val = atoi(argv[3]);
            CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFNumberRef)@(val), (__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
            CFPreferencesSynchronize((__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
            notify_post("com.makr.lineageqs/prefs-changed");
            printf("%s = %ld\n", key.UTF8String, (long)val);
        } else if ([cmd isEqualToString:@"backend"] && argc > 2) {
            // lqsctl backend dump <Class> | state <tile> | set <tile> 0|1 | brightness <0..1>  (needs DEBUG flag)
            NSMutableArray *w = [NSMutableArray array];
            for (int i = 2; i < argc; i++) [w addObject:@(argv[i])];
            NSString *outPath = [kDir stringByAppendingPathComponent:@"cmd.out"];
            [fm removeItemAtPath:outPath error:nil];
            [[w componentsJoinedByString:@" "] writeToFile:[kDir stringByAppendingPathComponent:@"cmd"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            notify_post("com.makr.lineageqs/debug-backend");
            for (int i = 0; i < 30 && ![fm fileExistsAtPath:outPath]; i++) usleep(100000);
            NSString *out = [NSString stringWithContentsOfFile:outPath encoding:NSUTF8StringEncoding error:nil];
            printf("%s\n", out ? out.UTF8String : "(no answer: DEBUG flag missing or SpringBoard busy)");
        } else if ([cmd isEqualToString:@"reset"]) {
            notify_post("com.makr.lineageqs/reset-layout");
            printf("layout reset requested\n");
        } else if ([cmd hasPrefix:@"debug-"]) {
            notify_post([@"com.makr.lineageqs/" stringByAppendingString:cmd].UTF8String);
            printf("posted %s\n", cmd.UTF8String);
        } else {
            id en = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("enabled"), (__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost));
            for (NSString *k in @[@"bottomSwipe", @"topSwipe", @"topSwipeSplit", @"topRoute"]) {
                id v = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)k, (__bridge CFStringRef)kDomain, CFSTR("mobile"), kCFPreferencesAnyHost));
                printf("%s=%s ", k.UTF8String, v ? [[v description] UTF8String] : "default");
            }
            printf("\nenabled=%s killSwitch=%s debug=%s\n", [en boolValue] ? "YES" : "NO",
                   [fm fileExistsAtPath:kill] ? "present" : "absent",
                   [fm fileExistsAtPath:[kDir stringByAppendingPathComponent:@"DEBUG"]] ? "present" : "absent");
        }
    }
    return 0;
}
