// Port of upstream/aosp-libmonet/contrast/Contrast.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Java static final double constants -> class methods with the constant's name (e.g. +RATIO_MIN).
// Java private constructor is omitted (utility class, no instances).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUContrast : NSObject

/** The minimum contrast ratio of two colors (1.0). */
+ (double)RATIO_MIN;
/** The maximum contrast ratio of two colors (21.0). */
+ (double)RATIO_MAX;
+ (double)RATIO_30;
+ (double)RATIO_45;
+ (double)RATIO_70;

/** Contrast ratio from two Y values (XYZ relative luminance). */
+ (double)ratioOfYs:(double)y1 y2:(double)y2;

/** Contrast ratio of two tones (T in HCT, L* in L*a*b*). */
+ (double)ratioOfTones:(double)t1 t2:(double)t2;

/** T/L* >= tone that ensures ratio with input tone. Returns -1 if the ratio cannot be achieved. */
+ (double)lighter:(double)tone ratio:(double)ratio;

/** Tone >= tone that ensures ratio. 100 if ratio cannot be achieved (unsafe). */
+ (double)lighterUnsafe:(double)tone ratio:(double)ratio;

/** T/L* <= tone that ensures ratio with input tone. Returns -1 if the ratio cannot be achieved. */
+ (double)darker:(double)tone ratio:(double)ratio;

/** Tone <= tone that ensures ratio. 0 if ratio cannot be achieved (unsafe). */
+ (double)darkerUnsafe:(double)tone ratio:(double)ratio;

@end

NS_ASSUME_NONNULL_END
