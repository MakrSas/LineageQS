// Port of upstream/aosp-libmonet/palettes/CorePalettes.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUCorePalettes.h"
#import "MCUTonalPalette.h"

@implementation MCUCorePalettes

- (instancetype)initWithPrimary:(MCUTonalPalette *)primary
                      secondary:(MCUTonalPalette *)secondary
                       tertiary:(MCUTonalPalette *)tertiary
                        neutral:(MCUTonalPalette *)neutral
                  neutralVariant:(MCUTonalPalette *)neutralVariant {
  self = [super init];
  if (self) {
    _primary = primary;
    _secondary = secondary;
    _tertiary = tertiary;
    _neutral = neutral;
    _neutralVariant = neutralVariant;
  }
  return self;
}

@end
