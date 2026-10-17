// Port of upstream/aosp-libmonet/hct/Hct.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Overloads: none. Java toString() -> description. Java private constructor Hct(int argb) is
// declared in the .m as initWithArgb:. Java private setInternalState(int) is in the .m.

#import <Foundation/Foundation.h>

@class MCUViewingConditions;

NS_ASSUME_NONNULL_BEGIN

@interface MCUHct : NSObject

/** Create an HCT color from hue (0..360), chroma and tone (0..100). Invalid values are corrected. */
+ (MCUHct *)from:(double)hue chroma:(double)chroma tone:(double)tone;

/** Create an HCT color from an ARGB color. */
+ (MCUHct *)fromInt:(int)argb;

- (double)getHue;
- (double)getChroma;
- (double)getTone;
- (int)toInt;

/** Set the hue of this color. Chroma may decrease. */
- (void)setHue:(double)newHue;

/** Set the chroma of this color. Chroma may decrease. */
- (void)setChroma:(double)newChroma;

/** Set the tone of this color. Chroma may decrease. */
- (void)setTone:(double)newTone;

/** "HCT(hue, chroma, tone)" with each value rounded like Java Math.round. */
- (NSString *)description;

+ (BOOL)isBlue:(double)hue;
+ (BOOL)isYellow:(double)hue;
+ (BOOL)isCyan:(double)hue;

/** Translate a color into different ViewingConditions. */
- (MCUHct *)inViewingConditions:(MCUViewingConditions *)vc;

@end

NS_ASSUME_NONNULL_END
