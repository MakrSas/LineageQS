// Port of upstream/aosp-libmonet/quantize/QuantizerMap.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import <Foundation/Foundation.h>
#import "MCUQuantizer.h"

NS_ASSUME_NONNULL_BEGIN

@interface MCUQuantizerMap : NSObject <MCUQuantizer>

- (NSDictionary<NSNumber *, NSNumber *> *)getColorToCount;

@end

NS_ASSUME_NONNULL_END
