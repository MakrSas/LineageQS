// Port of the KeyColor inner class of upstream/aosp-libmonet/palettes/TonalPalette.java
// (libmonet, Apache License 2.0, Copyright Google LLC). Inner class of TonalPalette -> MCUKeyColor.
//
// Java private helper maxChroma(int) is declared in the .m.

#import <Foundation/Foundation.h>

@class MCUHct;

NS_ASSUME_NONNULL_BEGIN

@interface MCUKeyColor : NSObject

/** Key color is a color that represents the hue and chroma of a tonal palette. */
- (instancetype)initWithHue:(double)hue requestedChroma:(double)requestedChroma;

/**
 * Creates a key color from a hue and a chroma. The key color is the first tone, starting from T50,
 * matching the given hue and chroma.
 */
- (MCUHct *)create;

@end

NS_ASSUME_NONNULL_END
