// Port of upstream/aosp-libmonet/score/Score.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes:
//  - Java `Map<Integer, Integer>` is NSDictionary<NSNumber *, NSNumber *>. Java iterates a LinkedHashMap
//    in insertion order, and the order decides ties in the stable sort; use the keyOrder variant with
//    MCUQuantizerResult.colorOrder to be bit-exact. The overloads without keyOrder iterate the
//    dictionary's allKeys (unordered), so they are only suitable when no two scored colors tie.
//  - Java `List<Integer>` is NSArray<NSNumber *>.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUScore : NSObject

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation;

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                       desired:(int)desired;

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb;

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb
                        filter:(BOOL)filter;

/** Full Java overload, with the map iteration order given explicitly (LinkedHashMap order). */
+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                      keyOrder:(NSArray<NSNumber *> *)keyOrder
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb
                        filter:(BOOL)filter;

@end

NS_ASSUME_NONNULL_END
