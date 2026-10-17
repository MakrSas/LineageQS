// Current iOS wallpaper image: SpringBoard stores it as a CPBitmap file
// (/var/mobile/Library/SpringBoard/{Home,Lock}Background.cpbitmap); AppSupport's
// CPBitmapCreateImagesFromData decodes it. Resolved at runtime (private API).
#import "LQSWallpaper.h"
#import <dlfcn.h>

typedef CFArrayRef (*CPBitmapCreateImagesFromDataFn)(CFDataRef data, void *unknown, int count, void *unknown2);

@implementation LQSWallpaper

+ (UIImage *)currentImage {
    static CPBitmapCreateImagesFromDataFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
        if (h) fn = (CPBitmapCreateImagesFromDataFn)dlsym(h, "CPBitmapCreateImagesFromData");
    });
    NSString *dir = @"/var/mobile/Library/SpringBoard";
    for (NSString *name in @[@"HomeBackground.cpbitmap", @"LockBackground.cpbitmap", @"HomeBackgroundThumbnail.jpg", @"LockBackgroundThumbnail.jpg"]) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSData *d = [NSData dataWithContentsOfFile:path];
        if (!d.length) continue;
        if ([name hasSuffix:@".jpg"]) { UIImage *img = [UIImage imageWithData:d]; if (img) return img; continue; }
        if (!fn) continue;
        CFArrayRef images = fn((__bridge CFDataRef)d, NULL, 1, NULL);
        if (!images) continue;
        UIImage *img = nil;
        if (CFArrayGetCount(images) > 0) {
            CGImageRef cg = (CGImageRef)CFArrayGetValueAtIndex(images, 0);
            if (cg) img = [UIImage imageWithCGImage:cg];
        }
        CFRelease(images);
        if (img) return img;
    }
    return nil;
}

@end
