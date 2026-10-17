// Port of upstream/aosp-libmonet/quantize/QuantizerResult.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes: `colorToCount` is the Java Map; `colorOrder` is the Java LinkedHashMap key order
// (first insertion order, duplicates keep their first position).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUQuantizerResult : NSObject

@property (nonatomic, readonly) NSDictionary<NSNumber *, NSNumber *> *colorToCount;
@property (nonatomic, readonly) NSArray<NSNumber *> *colorOrder;

- (instancetype)initWithColorToCount:(NSDictionary<NSNumber *, NSNumber *> *)colorToCount
                          colorOrder:(NSArray<NSNumber *> *)colorOrder;

@end

NS_ASSUME_NONNULL_END
