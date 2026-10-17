// Port of upstream/aosp-libmonet/quantize/QuantizerCelebi.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import "MCUQuantizerCelebi.h"
#import "MCUQuantizerResult.h"
#import "MCUQuantizerWu.h"
#import "MCUQuantizerWsmeans.h"

@implementation MCUQuantizerCelebi

+ (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)pixels maxColors:(int)maxColors {
  MCUQuantizerWu *wu = [[MCUQuantizerWu alloc] init];
  MCUQuantizerResult *wuResult = [wu quantize:pixels maxColors:maxColors];

  // wuResult.colorToCount.keySet() in LinkedHashMap order.
  NSArray<NSNumber *> *wuClusters = wuResult.colorOrder;

  return [MCUQuantizerWsmeans quantize:pixels startingClusters:wuClusters maxColors:maxColors];
}

@end
