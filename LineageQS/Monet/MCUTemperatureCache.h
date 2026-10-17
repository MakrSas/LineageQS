// Port of upstream/aosp-libmonet/temperature/TemperatureCache.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Overloads: getAnalogousColors() -> getAnalogousColors (5 colors, 12 divisions);
// getAnalogousColors(int count, int divisions) -> getAnalogousColors:divisions:.
// Java private no-arg constructor (throws) is omitted. Java private helpers are declared in the .m.

#import <Foundation/Foundation.h>

@class MCUHct;

NS_ASSUME_NONNULL_BEGIN

@interface MCUTemperatureCache : NSObject

/** Create a cache that allows calculation of ex. complementary and analogous colors. */
- (instancetype)initWithInput:(MCUHct *)input;

/** A color that complements the input color aesthetically. */
- (MCUHct *)getComplement;

/** 5 colors that pair well with the input color (equidistant in temperature, adjacent in hue). */
- (NSArray<MCUHct *> *)getAnalogousColors;

/**
 * A set of colors with differing hues, equidistant in temperature.
 * Behavior is undefined when count or divisions is 0. When divisions < count, colors repeat.
 */
- (NSArray<MCUHct *> *)getAnalogousColors:(int)count divisions:(int)divisions;

/** Temperature relative to all colors with the same chroma and tone, on a scale from 0 to 1. */
- (double)getRelativeTemperature:(MCUHct *)hct;

/** Value representing cool-warm factor of a color. Values below 0 are cool, above, warm. */
+ (double)rawTemperature:(MCUHct *)color;

@end

NS_ASSUME_NONNULL_END
