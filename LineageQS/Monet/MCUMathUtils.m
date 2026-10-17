// Port of upstream/aosp-libmonet/utils/MathUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUMathUtils.h"

@implementation MCUMathUtils

+ (int)signum:(double)num {
  if (num < 0) {
    return -1;
  } else if (num == 0) {
    return 0;
  } else {
    return 1;
  }
}

+ (double)lerp:(double)start stop:(double)stop amount:(double)amount {
  return (1.0 - amount) * start + amount * stop;
}

+ (int)clampInt:(int)min max:(int)max input:(int)input {
  if (input < min) {
    return min;
  } else if (input > max) {
    return max;
  }
  return input;
}

+ (double)clampDouble:(double)min max:(double)max input:(double)input {
  if (input < min) {
    return min;
  } else if (input > max) {
    return max;
  }
  return input;
}

+ (int)sanitizeDegreesInt:(int)degrees {
  degrees = degrees % 360;
  if (degrees < 0) {
    degrees = degrees + 360;
  }
  return degrees;
}

+ (double)sanitizeDegreesDouble:(double)degrees {
  degrees = fmod(degrees, 360.0);
  if (degrees < 0) {
    degrees = degrees + 360.0;
  }
  return degrees;
}

+ (double)rotationDirection:(double)from to:(double)to {
  double increasingDifference = [MCUMathUtils sanitizeDegreesDouble:to - from];
  return increasingDifference <= 180.0 ? 1.0 : -1.0;
}

+ (double)differenceDegrees:(double)a b:(double)b {
  return 180.0 - fabs(fabs(a - b) - 180.0);
}

+ (NSArray<NSNumber *> *)matrixMultiply:(NSArray<NSNumber *> *)row matrix:(const double (*)[3])matrix {
  double r0 = MCUVecGet(row, 0);
  double r1 = MCUVecGet(row, 1);
  double r2 = MCUVecGet(row, 2);
  double a = r0 * matrix[0][0] + r1 * matrix[0][1] + r2 * matrix[0][2];
  double b = r0 * matrix[1][0] + r1 * matrix[1][1] + r2 * matrix[1][2];
  double c = r0 * matrix[2][0] + r1 * matrix[2][1] + r2 * matrix[2][2];
  return MCUVec3(a, b, c);
}

@end
