// Port of upstream/aosp-libmonet/utils/ColorUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Java boolean -> BOOL. Java double[] -> NSArray<NSNumber *> * (3 elements).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUColorUtils : NSObject

/** Converts a color from RGB components to ARGB format. */
+ (int)argbFromRgb:(int)red green:(int)green blue:(int)blue;

/** Converts a color from linear RGB components to ARGB format. */
+ (int)argbFromLinrgb:(NSArray<NSNumber *> *)linrgb;

/** Returns the alpha component of a color in ARGB format. */
+ (int)alphaFromArgb:(int)argb;

/** Returns the red component of a color in ARGB format. */
+ (int)redFromArgb:(int)argb;

/** Returns the green component of a color in ARGB format. */
+ (int)greenFromArgb:(int)argb;

/** Returns the blue component of a color in ARGB format. */
+ (int)blueFromArgb:(int)argb;

/** Returns whether a color in ARGB format is opaque. */
+ (BOOL)isOpaque:(int)argb;

/** Converts a color from XYZ to ARGB. */
+ (int)argbFromXyz:(double)x y:(double)y z:(double)z;

/** Converts a color from ARGB to XYZ. */
+ (NSArray<NSNumber *> *)xyzFromArgb:(int)argb;

/** Converts a color represented in Lab color space into an ARGB integer. */
+ (int)argbFromLab:(double)l a:(double)a b:(double)b;

/** Converts a color from ARGB representation to L*a*b* representation. Returns [l, a, b]. */
+ (NSArray<NSNumber *> *)labFromArgb:(int)argb;

/** Converts an L* value to an ARGB representation of a grayscale color. */
+ (int)argbFromLstar:(double)lstar;

/** Computes the L* value of a color in ARGB representation. */
+ (double)lstarFromArgb:(int)argb;

/** Converts an L* value to a Y value (XYZ). */
+ (double)yFromLstar:(double)lstar;

/** Converts a Y value (XYZ) to an L* value. */
+ (double)lstarFromY:(double)y;

/** Linearizes an RGB component, 0 <= rgbComponent <= 255, output 0.0 <= output <= 100.0. */
+ (double)linearized:(int)rgbComponent;

/** Delinearizes an RGB component, 0.0 <= rgbComponent <= 100.0, output 0 <= output <= 255. */
+ (int)delinearized:(double)rgbComponent;

/** Returns the standard white point (D65); white on a sunny day. Returns [95.047, 100.0, 108.883]. */
+ (NSArray<NSNumber *> *)whitePointD65;

/** Lab f function (package-private in Java). */
+ (double)labF:(double)t;

/** Inverse of the Lab f function (package-private in Java). */
+ (double)labInvf:(double)ft;

@end

NS_ASSUME_NONNULL_END
