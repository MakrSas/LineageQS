// Port of upstream/aosp-libmonet/palettes/CorePalette.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUCorePalette.h"
#import "MCUHct.h"
#import "MCUMathUtils.h"
#import "MCUTonalPalette.h"

@interface MCUCorePalette ()
- (instancetype)initWithArgb:(int)argb isContent:(BOOL)isContent;
@end

@implementation MCUCorePalette

+ (MCUCorePalette *)of:(int)argb {
  return [[MCUCorePalette alloc] initWithArgb:argb isContent:NO];
}

+ (MCUCorePalette *)contentOf:(int)argb {
  return [[MCUCorePalette alloc] initWithArgb:argb isContent:YES];
}

- (instancetype)initWithArgb:(int)argb isContent:(BOOL)isContent {
  self = [super init];
  if (self) {
    MCUHct *hct = [MCUHct fromInt:argb];
    double hue = [hct getHue];
    double chroma = [hct getChroma];
    if (isContent) {
      _a1 = [MCUTonalPalette fromHueAndChroma:hue chroma:chroma];
      _a2 = [MCUTonalPalette fromHueAndChroma:hue chroma:chroma / 3.0];
      _a3 = [MCUTonalPalette fromHueAndChroma:hue + 60.0 chroma:chroma / 2.0];
      _n1 = [MCUTonalPalette fromHueAndChroma:hue chroma:MCUJavaMin(chroma / 12.0, 4.0)];
      _n2 = [MCUTonalPalette fromHueAndChroma:hue chroma:MCUJavaMin(chroma / 6.0, 8.0)];
    } else {
      _a1 = [MCUTonalPalette fromHueAndChroma:hue chroma:MCUJavaMax(48.0, chroma)];
      _a2 = [MCUTonalPalette fromHueAndChroma:hue chroma:16.0];
      _a3 = [MCUTonalPalette fromHueAndChroma:hue + 60.0 chroma:24.0];
      _n1 = [MCUTonalPalette fromHueAndChroma:hue chroma:4.0];
      _n2 = [MCUTonalPalette fromHueAndChroma:hue chroma:8.0];
    }
    _error = [MCUTonalPalette fromHueAndChroma:25.0 chroma:84.0];
  }
  return self;
}

@end
