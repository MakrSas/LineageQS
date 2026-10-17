#import "LQSMedia.h"
#import <dlfcn.h>
#import <objc/message.h>

NSString *const LQSMediaChangedNotification = @"LQSMediaChangedNotification";

static void *MR(void) {
    static void *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY); });
    return h;
}

@implementation LQSMedia {
    NSTimeInterval _elapsedAt;   // elapsed at _stamp
    NSDate *_stamp;
    double _rate;
}

+ (instancetype)shared {
    static LQSMedia *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [LQSMedia new]; });
    return m;
}

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (*reg)(dispatch_queue_t) = (void (*)(dispatch_queue_t))dlsym(MR(), "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (reg) reg(dispatch_get_main_queue());
        for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:n object:nil];
        }
    });
    [self refresh];
}

- (NSTimeInterval)elapsed {
    if (!_stamp) return _elapsedAt;
    NSTimeInterval e = _elapsedAt + (_rate > 0 ? -[_stamp timeIntervalSinceNow] * _rate : 0);
    return _duration > 0 ? MIN(e, _duration) : e;
}

- (void)refresh {
    void (*get)(dispatch_queue_t, void (^)(CFDictionaryRef)) = (void (*)(dispatch_queue_t, void (^)(CFDictionaryRef)))dlsym(MR(), "MRMediaRemoteGetNowPlayingInfo");
    if (!get) return;
    get(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        if (![d isKindOfClass:NSDictionary.class]) d = @{};
        self->_title = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
        self->_artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSData *art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        self->_artwork = [art isKindOfClass:NSData.class] ? [UIImage imageWithData:art] : nil;
        self->_duration = [d[@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue];
        self->_elapsedAt = [d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
        id ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        self->_stamp = [ts isKindOfClass:NSDate.class] ? ts : [NSDate date];
        self->_rate = [d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue];
        // Playing state + app from SpringBoard's own media controller.
        Class mc = NSClassFromString(@"SBMediaController");
        id c = [mc respondsToSelector:@selector(sharedInstance)] ? [mc performSelector:@selector(sharedInstance)] : nil;
        self->_playing = [c respondsToSelector:NSSelectorFromString(@"isPlaying")] ? ((BOOL (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"isPlaying")) : self->_rate > 0;
        id app = [c respondsToSelector:NSSelectorFromString(@"nowPlayingApplication")] ? ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"nowPlayingApplication")) : nil;
        self->_bundleID = [app respondsToSelector:NSSelectorFromString(@"bundleIdentifier")] ? [app valueForKey:@"bundleIdentifier"] : nil;
        self->_appName = [app respondsToSelector:NSSelectorFromString(@"displayName")] ? [app valueForKey:@"displayName"] : nil;
        self->_hasMedia = [self->_title isKindOfClass:NSString.class] && self->_title.length > 0;
        [[NSNotificationCenter defaultCenter] postNotificationName:LQSMediaChangedNotification object:self];
    });
}

- (void)send:(unsigned)cmd {
    Boolean (*send)(unsigned, CFDictionaryRef) = (Boolean (*)(unsigned, CFDictionaryRef))dlsym(MR(), "MRMediaRemoteSendCommand");
    if (send) send(cmd, NULL);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self refresh]; });
}
// MRMediaRemoteCommand: 2 togglePlayPause, 4 nextTrack, 5 previousTrack.
- (void)togglePlayPause { [self send:2]; }
- (void)next { [self send:4]; }
- (void)previous { [self send:5]; }
- (void)seekTo:(NSTimeInterval)t {
    void (*seek)(double) = (void (*)(double))dlsym(MR(), "MRMediaRemoteSetElapsedTime");
    if (seek) seek(t);
    _elapsedAt = t; _stamp = [NSDate date];
}
@end
