// Port of upstream/aosp-libmonet/utils/StringUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUStringUtils : NSObject

/** Hex string representing color, ex. #ff0000 for red (lowercase, as Java String.format("#%02x%02x%02x")). */
+ (NSString *)hexFromArgb:(int)argb;

@end

NS_ASSUME_NONNULL_END
