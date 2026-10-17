#import "LQSNotifications.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const LQSNotificationsChangedNotification = @"LQSNotificationsChangedNotification";

static id V(id obj, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    Method m = class_getInstanceMethod([obj class], s);
    if (m) {
        char *ret = method_copyReturnType(m);
        BOOL isObj = ret[0] == '@';
        free(ret);
        if (!isObj) return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

@interface LQSNotificationItem ()
@property (nonatomic, strong, readwrite) id request;
@property (nonatomic, copy, readwrite) NSString *identifier, *bundleID;
@property (nonatomic, copy, readwrite, nullable) NSString *threadID, *appName, *title, *subtitle, *message;
@property (nonatomic, strong, readwrite, nullable) NSDate *date;
@property (nonatomic, strong, readwrite, nullable) UIImage *icon, *attachment;
@end

@implementation LQSNotificationItem
+ (instancetype)itemWithRequest:(id)req {
    LQSNotificationItem *it = [self new];
    it.request = req;
    it.identifier = Str(V(req, @"notificationIdentifier")) ?: [NSString stringWithFormat:@"%p", req];
    it.bundleID = Str(V(req, @"sectionIdentifier")) ?: @"";
    it.threadID = Str(V(req, @"threadIdentifier"));
    id ts = V(req, @"timestamp");
    it.date = [ts isKindOfClass:NSDate.class] ? ts : nil;
    id c = V(req, @"content");
    it.appName = Str(V(c, @"header"));
    it.title = Str(V(c, @"title"));
    it.subtitle = Str(V(c, @"subtitle"));
    it.message = Str(V(c, @"message"));
    id icon = V(c, @"icon");
    if (![icon isKindOfClass:UIImage.class]) { NSArray *icons = V(c, @"icons"); icon = [icons isKindOfClass:NSArray.class] ? icons.firstObject : nil; }
    it.icon = [icon isKindOfClass:UIImage.class] ? icon : nil;
    id att = V(c, @"attachmentImage");
    it.attachment = [att isKindOfClass:UIImage.class] ? att : nil;
    return it;
}
@end

@implementation LQSNotifications {
    NSMutableArray<LQSNotificationItem *> *_items;
}

+ (instancetype)shared {
    static LQSNotifications *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [LQSNotifications new]; s->_items = [NSMutableArray array]; });
    return s;
}

- (NSArray<LQSNotificationItem *> *)items {
    return [_items sortedArrayUsingComparator:^NSComparisonResult(LQSNotificationItem *a, LQSNotificationItem *b) {
        return [(b.date ?: NSDate.distantPast) compare:(a.date ?: NSDate.distantPast)];
    }];
}

- (NSUInteger)indexFor:(id)request {
    NSString *ident = Str(V(request, @"notificationIdentifier"));
    for (NSUInteger i = 0; i < _items.count; i++) {
        if (_items[i].request == request || (ident && [_items[i].identifier isEqualToString:ident])) return i;
    }
    return NSNotFound;
}

- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:LQSNotificationsChangedNotification object:self]; }

- (void)posted:(id)request {
    if (!request) return;
    LQSNotificationItem *it = [LQSNotificationItem itemWithRequest:request];
    NSUInteger i = [self indexFor:request];
    if (i == NSNotFound) [_items addObject:it]; else _items[i] = it;
    [self changed];
}

- (void)modified:(id)request { [self posted:request]; }

- (void)withdrawn:(id)request {
    NSUInteger i = [self indexFor:request];
    if (i == NSNotFound) return;
    [_items removeObjectAtIndex:i];
    [self changed];
}

- (NSArray *)allDestinations {
    id reg = V(self.dispatcher, @"destinationsRegistry");
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *sel in @[@"destinations", @"allDestinations", @"registeredDestinations", @"activeDestinations"]) {
        id d = V(reg, sel);
        if ([d isKindOfClass:NSSet.class] || [d isKindOfClass:NSHashTable.class]) for (id o in d) [out addObject:o];
        else if ([d isKindOfClass:NSArray.class]) [out addObjectsFromArray:d];
        else if ([d isKindOfClass:NSDictionary.class]) [out addObjectsFromArray:[d allValues]];
        if (out.count) break;
    }
    return out;
}

// The stock Notification Center list asks the dispatcher to clear on its own
// behalf; we pass the same destination (class name contains "NotificationList"
// / "Structured" / "NotificationCenter"), falling back to any destination.
- (id)anyDestination {
    NSArray *all = [self allDestinations];
    for (id d in all) {
        NSString *n = NSStringFromClass([d class]);
        // On iOS 16 the Notification Center list is the cover sheet's destination
        // (CSNotificationDispatcher); NCNotificationAlertQueue is the banner queue.
        if ([n hasPrefix:@"CS"] || [n containsString:@"CoverSheet"] || [n containsString:@"List"] || [n containsString:@"NotificationCenter"]) return d;
    }
    return all.firstObject;
}

- (BOOL)openItem:(LQSNotificationItem *)item {
    id action = V(item.request, @"defaultAction");
    SEL sel = NSSelectorFromString(@"destination:executeAction:forNotificationRequest:requestAuthentication:withParameters:completion:");
    if (!action) return NO;
    if (![self.dispatcher respondsToSelector:sel]) {
        // Fallback: the action's own runner (NCNotificationActionRunner).
        id runner = V(action, @"actionRunner");
        SEL rs = NSSelectorFromString(@"executeAction:fromOrigin:endpoint:withParameters:completion:");
        if (![runner respondsToSelector:rs]) return NO;
        ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(runner, rs, action, nil, nil, @{}, nil);
        return YES;
    }
    ((void (*)(id, SEL, id, id, id, BOOL, id, id))objc_msgSend)(self.dispatcher, sel, [self anyDestination], action, item.request, YES, @{}, ^(BOOL ok) {
        NSLog(@"[LineageQS] notification open -> %d", ok);
    });
    return YES;
}

- (BOOL)clearItems:(NSArray<LQSNotificationItem *> *)items {
    if (!items.count) return NO;
    SEL sel = NSSelectorFromString(@"destination:requestsClearingNotificationRequests:");
    if (![self.dispatcher respondsToSelector:sel]) return NO;
    NSMutableSet *reqs = [NSMutableSet set];
    for (LQSNotificationItem *it in items) [reqs addObject:it.request];
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.dispatcher, sel, [self anyDestination], reqs);
    return YES;
}

- (NSString *)debugListing {
    NSMutableArray *names = [NSMutableArray array];
    for (id d in [self allDestinations]) [names addObject:NSStringFromClass([d class])];
    NSMutableString *m = [NSMutableString stringWithFormat:@"%lu notifications, dispatcher=%@ chosen=%@\ndestinations=%@\n", (unsigned long)_items.count,
                          self.dispatcher ? NSStringFromClass([self.dispatcher class]) : @"nil", NSStringFromClass([[self anyDestination] class]), names];
    for (LQSNotificationItem *it in self.items) {
        // Content is not logged (privacy): app, presence of fields only.
        [m appendFormat:@"- %@ app=%@ title=%d msg=%d icon=%d att=%d thread=%d date=%@\n", it.bundleID, it.appName ?: @"-", it.title != nil, it.message != nil,
                         it.icon != nil, it.attachment != nil, it.threadID != nil, it.date];
    }
    return m;
}

@end
