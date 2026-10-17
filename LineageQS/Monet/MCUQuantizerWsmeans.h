// Port of upstream/aosp-libmonet/quantize/QuantizerWsmeans.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes: Java returns Map<Integer, Integer>; this port returns MCUQuantizerResult, which carries
// the same map plus its LinkedHashMap insertion order (needed for bit-exact Score results).

#import <Foundation/Foundation.h>

@class MCUQuantizerResult;

NS_ASSUME_NONNULL_BEGIN

@interface MCUQuantizerWsmeans : NSObject

+ (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)inputPixels
                startingClusters:(NSArray<NSNumber *> *)startingClusters
                       maxColors:(int)maxColors;

@end

NS_ASSUME_NONNULL_END
