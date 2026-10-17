// Port of upstream/aosp-libmonet/utils/StringUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUStringUtils.h"
#import "MCUColorUtils.h"

@implementation MCUStringUtils

+ (NSString *)hexFromArgb:(int)argb {
  int red = [MCUColorUtils redFromArgb:argb];
  int blue = [MCUColorUtils blueFromArgb:argb];
  int green = [MCUColorUtils greenFromArgb:argb];
  return [NSString stringWithFormat:@"#%02x%02x%02x", (unsigned)red, (unsigned)green, (unsigned)blue];
}

@end
