// Port of upstream/aosp-libmonet/palettes/TonalPalette.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Overloads: none in Java with the same name. Java private constructor
// TonalPalette(double hue, double chroma, Hct keyColor) -> initWithHue:chroma:keyColor: (in .m).
// Java private averageArgb(int, int) -> averageArgb:argb2: (in .m).
// NOTE: the Java method fromHueAndChroma(double hue, double chroma) is named fromHueAndChroma:chroma:.

#import <Foundation/Foundation.h>

@class MCUHct;

NS_ASSUME_NONNULL_BEGIN

@interface MCUTonalPalette : NSObject

/** Create tones using the HCT hue and chroma from a color. */
+ (MCUTonalPalette *)fromInt:(int)argb;

/** Create tones using a HCT color. */
+ (MCUTonalPalette *)fromHct:(MCUHct *)hct;

/** Create tones from a defined HCT hue and chroma. */
+ (MCUTonalPalette *)fromHueAndChroma:(double)hue chroma:(double)chroma;

/** ARGB color with HCT hue and chroma of this palette, and the given HCT tone (0..100). */
- (int)tone:(int)tone;

/** Given a tone, use hue and chroma of palette to create a color, and return it as HCT. */
- (MCUHct *)getHct:(double)tone;

/** The chroma of the Tonal Palette, in HCT. */
- (double)getChroma;

/** The hue of the Tonal Palette, in HCT. */
- (double)getHue;

/** The key color is the first tone, starting from T50, that matches the palette's chroma. */
- (MCUHct *)getKeyColor;

@end

NS_ASSUME_NONNULL_END
