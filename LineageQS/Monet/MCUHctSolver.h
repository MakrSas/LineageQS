// Port of upstream/aosp-libmonet/hct/HctSolver.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Java double[] parameters/returns -> NSArray<NSNumber *> (3 elements). Java double[][] tables are
// C static arrays in the .m. Java package-private static methods are exposed here as class methods.

#import <Foundation/Foundation.h>

@class MCUCam16;

NS_ASSUME_NONNULL_BEGIN

@interface MCUHctSolver : NSObject

/** Sanitizes a small enough angle in radians; returns a coterminal angle between 0 and 2pi. */
+ (double)sanitizeRadians:(double)angle;

/** Delinearizes an RGB component, returning a floating-point number (0.0 .. 255.0). */
+ (double)trueDelinearized:(double)rgbComponent;

+ (double)chromaticAdaptation:(double)component;

/** Returns the hue of a linear RGB color in CAM16, in radians. */
+ (double)hueOf:(NSArray<NSNumber *> *)linrgb;

+ (BOOL)areInCyclicOrder:(double)a b:(double)b c:(double)c;

/** Solves the lerp equation: t such that lerp(source, target, t) = mid. */
+ (double)intercept:(double)source mid:(double)mid target:(double)target;

+ (NSArray<NSNumber *> *)lerpPoint:(NSArray<NSNumber *> *)source
                                 t:(double)t
                            target:(NSArray<NSNumber *> *)target;

/** Intersects segment source-target with the plane coordinate on the given axis (0: R, 1: G, 2: B). */
+ (NSArray<NSNumber *> *)setCoordinate:(NSArray<NSNumber *> *)source
                            coordinate:(double)coordinate
                                target:(NSArray<NSNumber *> *)target
                                  axis:(int)axis;

+ (BOOL)isBounded:(double)x;

/** The nth possible vertex of the polygonal intersection of the y plane and the RGB cube. */
+ (NSArray<NSNumber *> *)nthVertex:(double)y n:(int)n;

/** Finds the segment containing the desired color. Returns [left, right]. */
+ (NSArray<NSArray<NSNumber *> *> *)bisectToSegment:(double)y targetHue:(double)targetHue;

+ (NSArray<NSNumber *> *)midpoint:(NSArray<NSNumber *> *)a b:(NSArray<NSNumber *> *)b;

+ (int)criticalPlaneBelow:(double)x;
+ (int)criticalPlaneAbove:(double)x;

/** Finds a color with the given Y and hue on the boundary of the cube, linear RGB. */
+ (NSArray<NSNumber *> *)bisectToLimit:(double)y targetHue:(double)targetHue;

+ (double)inverseChromaticAdaptation:(double)adapted;

/** Finds a color with the given hue, chroma, and Y; ARGB, or 0 if not found. */
+ (int)findResultByJ:(double)hueRadians chroma:(double)chroma y:(double)y;

/** Finds an sRGB color with the given hue (degrees), chroma, and L*, as ARGB. */
+ (int)solveToInt:(double)hueDegrees chroma:(double)chroma lstar:(double)lstar;

/** Finds an sRGB color with the given hue (degrees), chroma, and L*, as CAM16. */
+ (MCUCam16 *)solveToCam:(double)hueDegrees chroma:(double)chroma lstar:(double)lstar;

@end

NS_ASSUME_NONNULL_END
