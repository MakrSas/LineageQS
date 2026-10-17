// Port of upstream/aosp-libmonet/quantize/QuantizerMap.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import "MCUQuantizerMap.h"
#import "MCUQuantizerResult.h"

@implementation MCUQuantizerMap {
  NSDictionary<NSNumber *, NSNumber *> *_colorToCount;
}

- (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)pixels maxColors:(int)colorCount {
  // LinkedHashMap: insertion order = first occurrence of each pixel.
  NSMutableDictionary<NSNumber *, NSNumber *> *pixelByCount = [NSMutableDictionary dictionary];
  NSMutableArray<NSNumber *> *order = [NSMutableArray array];
  for (NSNumber *value in pixels) {
    NSNumber *pixel = @([value intValue]);
    NSNumber *currentPixelCount = pixelByCount[pixel];
    if (currentPixelCount == nil) {
      [order addObject:pixel];
    }
    int newPixelCount = currentPixelCount == nil ? 1 : [currentPixelCount intValue] + 1;
    pixelByCount[pixel] = @(newPixelCount);
  }
  _colorToCount = pixelByCount;
  return [[MCUQuantizerResult alloc] initWithColorToCount:pixelByCount colorOrder:order];
}

- (NSDictionary<NSNumber *, NSNumber *> *)getColorToCount {
  return _colorToCount;
}

@end
