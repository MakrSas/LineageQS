// Port of upstream/aosp-libmonet/quantize/QuantizerResult.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import "MCUQuantizerResult.h"

@implementation MCUQuantizerResult

- (instancetype)initWithColorToCount:(NSDictionary<NSNumber *, NSNumber *> *)colorToCount
                          colorOrder:(NSArray<NSNumber *> *)colorOrder {
  self = [super init];
  if (self) {
    _colorToCount = [colorToCount copy];
    _colorOrder = [colorOrder copy];
  }
  return self;
}

@end
