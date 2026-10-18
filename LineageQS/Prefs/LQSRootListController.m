#import <dlfcn.h>
#import "LQSRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import "LQSColorsViewController.h"
#import "LQSTheme.h"
#import "LQSVectorIcon.h"
#import "LQSStrings.h"

static NSString *L(NSString *k) { return [[NSBundle bundleForClass:NSClassFromString(@"LQSRootListController")] localizedStringForKey:k value:k table:@"Root"]; }

static NSString *LQSJBPath(NSString *path) {
    const char *(*jbroot)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    const char *r = jbroot ? jbroot(path.fileSystemRepresentation) : NULL;
    return r ? @(r) : [@"/var/jb" stringByAppendingString:path];
}

@implementation LQSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)openColors {
    NSString *root = nil;
    for (NSString *p in @[LQSJBPath(@"/Library/Application Support/LineageQS"), @"/Library/Application Support/LineageQS"])
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) { root = p; break; }
    if (!root) return;
    [LQSTheme setResourceRoot:root];
    [LQSVectorIcon setResourceDirectory:[root stringByAppendingPathComponent:@"vectors"]];
    LQSStringsSetDirectory([root stringByAppendingPathComponent:@"strings"]);
    [self presentViewController:[LQSColorsViewController new] animated:YES completion:nil];
}

- (void)resetLayout {
    CFPreferencesSetAppValue(CFSTR("layout"), NULL, CFSTR("com.makr.lineageqs"));
    CFPreferencesAppSynchronize(CFSTR("com.makr.lineageqs"));
    notify_post("com.makr.lineageqs/reset-layout");
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Раскладка сброшена")
        message:L(@"Плитки возвращены к набору Android 17 по умолчанию.") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)emergencyDisable {
    // Same effect as `lqsctl disable`: kill switch file + master off.
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/LineageQS" withIntermediateDirectories:YES attributes:nil error:nil];
    [@"" writeToFile:@"/var/mobile/Library/LineageQS/DISABLE" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CFPreferencesSetAppValue(CFSTR("enabled"), kCFBooleanFalse, CFSTR("com.makr.lineageqs"));
    CFPreferencesAppSynchronize(CFSTR("com.makr.lineageqs"));
    notify_post("com.makr.lineageqs/prefs-changed");
    [self reloadSpecifiers];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"LineageQS отключён")
        message:L(@"Создан /var/mobile/Library/LineageQS/DISABLE. Штатный Пункт управления восстановлен. Чтобы снова включить: удалите файл (или `lqsctl enable`) и перезапустите SpringBoard.") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
