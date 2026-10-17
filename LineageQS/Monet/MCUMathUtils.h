// Port of upstream/aosp-libmonet/utils/MathUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Conventions used by this port (see docs/monet-port.md):
//   double[]    -> NSArray<NSNumber *> * (3 elements for every Java double[] in libmonet)
//   double[][]  -> const double (*)[3]   (only 3x3 matrices exist in libmonet)
//   Java private members are declared only in the .m files.
//
// Java-semantics helpers (Math.round, (int) casts, Math.max/min, Math.signum, Double.compare,
// Math.toRadians/toDegrees) are defined below as static inline C functions so that every
// file in the port uses identical semantics.

#import <Foundation/Foundation.h>
#import <math.h>
#import <limits.h>
#import <string.h>

NS_ASSUME_NONNULL_BEGIN

// Java Math.round(double): returns long, half-up. Implemented as (long)floor(x + 0.5),
// NaN -> 0, saturating like Java.
static inline long MCUJavaRound(double x) {
  if (x != x) { return 0; }
  double f = floor(x + 0.5);
  if (f >= 9223372036854775807.0) { return LONG_MAX; }
  if (f <= -9223372036854775808.0) { return LONG_MIN; }
  return (long)f;
}

// Java (int) cast of a double: truncation, saturating, NaN -> 0.
static inline int MCUJavaD2I(double x) {
  if (x != x) { return 0; }
  if (x >= 2147483647.0) { return INT_MAX; }
  if (x <= -2147483648.0) { return INT_MIN; }
  return (int)x;
}

// Java Math.max(double, double): NaN-propagating, orders -0.0 below 0.0.
static inline double MCUJavaMax(double a, double b) {
  if (a != a) { return a; }
  if (a == 0.0 && b == 0.0 && signbit(a)) { return b; }
  return a >= b ? a : b;
}

// Java Math.min(double, double): NaN-propagating, orders -0.0 below 0.0.
static inline double MCUJavaMin(double a, double b) {
  if (a != a) { return a; }
  if (a == 0.0 && b == 0.0 && signbit(b)) { return b; }
  return a <= b ? a : b;
}

// Java Math.signum(double): returns the argument for 0 and NaN, otherwise +1.0 or -1.0.
static inline double MCUJavaSignum(double d) {
  if (d != d || d == 0.0) { return d; }
  return d > 0.0 ? 1.0 : -1.0;
}

// Java 9+ Math.toRadians / Math.toDegrees (multiplication by the rounded constants).
static inline double MCUJavaToRadians(double angdeg) { return angdeg * 0.017453292519943295; }
static inline double MCUJavaToDegrees(double angrad) { return angrad * 57.29577951308232; }

// Java Double.compare(a, b).
static inline int MCUJavaDoubleCompare(double a, double b) {
  if (a < b) { return -1; }
  if (a > b) { return 1; }
  uint64_t bitsA, bitsB;
  if (a != a) { bitsA = 0x7ff8000000000000ULL; } else { memcpy(&bitsA, &a, 8); }
  if (b != b) { bitsB = 0x7ff8000000000000ULL; } else { memcpy(&bitsB, &b, 8); }
  if (bitsA == bitsB) { return 0; }
  return ((int64_t)bitsA < (int64_t)bitsB) ? -1 : 1;
}

// double[3] helpers for the NSArray<NSNumber *> representation.
static inline NSArray<NSNumber *> *MCUVec3(double a, double b, double c) {
  return @[@(a), @(b), @(c)];
}
static inline double MCUVecGet(NSArray<NSNumber *> *v, NSUInteger i) {
  return [v[i] doubleValue];
}

@interface MCUMathUtils : NSObject

/** The signum function. Returns 1 if num > 0, -1 if num < 0, and 0 if num = 0 (int, as in Java). */
+ (int)signum:(double)num;

/** Linear interpolation: start if amount = 0, stop if amount = 1. */
+ (double)lerp:(double)start stop:(double)stop amount:(double)amount;

/** Clamps an integer between two integers. */
+ (int)clampInt:(int)min max:(int)max input:(int)input;

/** Clamps a double between two doubles. */
+ (double)clampDouble:(double)min max:(double)max input:(double)input;

/** Sanitizes a degree measure as an integer, result in [0, 360). */
+ (int)sanitizeDegreesInt:(int)degrees;

/** Sanitizes a degree measure as a double, result in [0.0, 360.0). */
+ (double)sanitizeDegreesDouble:(double)degrees;

/** Sign of direction change needed to travel from one angle to another (-1.0 or 1.0). */
+ (double)rotationDirection:(double)from to:(double)to;

/** Distance of two points on a circle, represented using degrees. */
+ (double)differenceDegrees:(double)a b:(double)b;

/** Multiplies a 1x3 row vector with a 3x3 matrix. */
+ (NSArray<NSNumber *> *)matrixMultiply:(NSArray<NSNumber *> *)row matrix:(const double (*)[3])matrix;

@end

NS_ASSUME_NONNULL_END
