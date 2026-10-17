// Port of upstream/aosp-libmonet/quantize/Quantizer.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes:
//  - Java `Map<Integer, Integer>` results are returned as MCUQuantizerResult, which keeps both the
//    dictionary (colorToCount) and the Java LinkedHashMap insertion order (colorOrder). The order is
//    observable by callers (Celebi feeds Wu's key order into Wsmeans, Score iterates in map order),
//    so it must be preserved for bit-exact results.
//  - Java `int[]` is represented as NSArray<NSNumber *> *.

#import <Foundation/Foundation.h>

@class MCUQuantizerResult;

NS_ASSUME_NONNULL_BEGIN

@protocol MCUQuantizer <NSObject>
- (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)pixels maxColors:(int)maxColors;
@end

NS_ASSUME_NONNULL_END
