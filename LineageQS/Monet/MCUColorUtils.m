// Port of upstream/aosp-libmonet/utils/ColorUtils.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUColorUtils.h"
#import "MCUMathUtils.h"

// Constant tables copied from ColorUtils.java.
static const double kMCUSrgbToXyz[3][3] = {
    {0.41233895, 0.35762064, 0.18051042},
    {0.2126, 0.7152, 0.0722},
    {0.01932141, 0.11916382, 0.95034478},
};
static const double kMCUXyzToSrgb[3][3] = {
    {3.2413774792388685, -1.5376652402851851, -0.49885366846268053},
    {-0.9691452513005321, 1.8758853451067872, 0.04156585616912061},
    {0.05562093689691305, -0.20395524564742123, 1.0571799111220335},
};
static const double kMCUWhitePointD65[3] = {
    95.047, 100.0, 108.883,
};

@implementation MCUColorUtils

+ (int)argbFromRgb:(int)red green:(int)green blue:(int)blue {
  return (int)((((unsigned)255) << 24) | (((unsigned)(red & 255)) << 16) | (((unsigned)(green & 255)) << 8) | ((unsigned)(blue & 255)));
}

+ (int)argbFromLinrgb:(NSArray<NSNumber *> *)linrgb {
  int r = [MCUColorUtils delinearized:MCUVecGet(linrgb, 0)];
  int g = [MCUColorUtils delinearized:MCUVecGet(linrgb, 1)];
  int b = [MCUColorUtils delinearized:MCUVecGet(linrgb, 2)];
  return [MCUColorUtils argbFromRgb:r green:g blue:b];
}

+ (int)alphaFromArgb:(int)argb {
  return (argb >> 24) & 255;
}

+ (int)redFromArgb:(int)argb {
  return (argb >> 16) & 255;
}

+ (int)greenFromArgb:(int)argb {
  return (argb >> 8) & 255;
}

+ (int)blueFromArgb:(int)argb {
  return argb & 255;
}

+ (BOOL)isOpaque:(int)argb {
  return [MCUColorUtils alphaFromArgb:argb] >= 255;
}

+ (int)argbFromXyz:(double)x y:(double)y z:(double)z {
  const double (*matrix)[3] = kMCUXyzToSrgb;
  double linearR = matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z;
  double linearG = matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z;
  double linearB = matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z;
  int r = [MCUColorUtils delinearized:linearR];
  int g = [MCUColorUtils delinearized:linearG];
  int b = [MCUColorUtils delinearized:linearB];
  return [MCUColorUtils argbFromRgb:r green:g blue:b];
}

+ (NSArray<NSNumber *> *)xyzFromArgb:(int)argb {
  double r = [MCUColorUtils linearized:[MCUColorUtils redFromArgb:argb]];
  double g = [MCUColorUtils linearized:[MCUColorUtils greenFromArgb:argb]];
  double b = [MCUColorUtils linearized:[MCUColorUtils blueFromArgb:argb]];
  return [MCUMathUtils matrixMultiply:MCUVec3(r, g, b) matrix:kMCUSrgbToXyz];
}

+ (int)argbFromLab:(double)l a:(double)a b:(double)b {
  const double *whitePoint = kMCUWhitePointD65;
  double fy = (l + 16.0) / 116.0;
  double fx = a / 500.0 + fy;
  double fz = fy - b / 200.0;
  double xNormalized = [MCUColorUtils labInvf:fx];
  double yNormalized = [MCUColorUtils labInvf:fy];
  double zNormalized = [MCUColorUtils labInvf:fz];
  double x = xNormalized * whitePoint[0];
  double y = yNormalized * whitePoint[1];
  double z = zNormalized * whitePoint[2];
  return [MCUColorUtils argbFromXyz:x y:y z:z];
}

+ (NSArray<NSNumber *> *)labFromArgb:(int)argb {
  double linearR = [MCUColorUtils linearized:[MCUColorUtils redFromArgb:argb]];
  double linearG = [MCUColorUtils linearized:[MCUColorUtils greenFromArgb:argb]];
  double linearB = [MCUColorUtils linearized:[MCUColorUtils blueFromArgb:argb]];
  const double (*matrix)[3] = kMCUSrgbToXyz;
  double x = matrix[0][0] * linearR + matrix[0][1] * linearG + matrix[0][2] * linearB;
  double y = matrix[1][0] * linearR + matrix[1][1] * linearG + matrix[1][2] * linearB;
  double z = matrix[2][0] * linearR + matrix[2][1] * linearG + matrix[2][2] * linearB;
  const double *whitePoint = kMCUWhitePointD65;
  double xNormalized = x / whitePoint[0];
  double yNormalized = y / whitePoint[1];
  double zNormalized = z / whitePoint[2];
  double fx = [MCUColorUtils labF:xNormalized];
  double fy = [MCUColorUtils labF:yNormalized];
  double fz = [MCUColorUtils labF:zNormalized];
  double l = 116.0 * fy - 16;
  double a = 500.0 * (fx - fy);
  double b = 200.0 * (fy - fz);
  return MCUVec3(l, a, b);
}

+ (int)argbFromLstar:(double)lstar {
  double y = [MCUColorUtils yFromLstar:lstar];
  int component = [MCUColorUtils delinearized:y];
  return [MCUColorUtils argbFromRgb:component green:component blue:component];
}

+ (double)lstarFromArgb:(int)argb {
  double y = MCUVecGet([MCUColorUtils xyzFromArgb:argb], 1);
  return 116.0 * [MCUColorUtils labF:y / 100.0] - 16.0;
}

+ (double)yFromLstar:(double)lstar {
  return 100.0 * [MCUColorUtils labInvf:(lstar + 16.0) / 116.0];
}

+ (double)lstarFromY:(double)y {
  return [MCUColorUtils labF:y / 100.0] * 116.0 - 16.0;
}

+ (double)linearized:(int)rgbComponent {
  double normalized = rgbComponent / 255.0;
  if (normalized <= 0.040449936) {
    return normalized / 12.92 * 100.0;
  } else {
    return pow((normalized + 0.055) / 1.055, 2.4) * 100.0;
  }
}

+ (int)delinearized:(double)rgbComponent {
  double normalized = rgbComponent / 100.0;
  double delinearized = 0.0;
  if (normalized <= 0.0031308) {
    delinearized = normalized * 12.92;
  } else {
    delinearized = 1.055 * pow(normalized, 1.0 / 2.4) - 0.055;
  }
  return [MCUMathUtils clampInt:0 max:255 input:(int)MCUJavaRound(delinearized * 255.0)];
}

+ (NSArray<NSNumber *> *)whitePointD65 {
  return MCUVec3(kMCUWhitePointD65[0], kMCUWhitePointD65[1], kMCUWhitePointD65[2]);
}

+ (double)labF:(double)t {
  double e = 216.0 / 24389.0;
  double kappa = 24389.0 / 27.0;
  if (t > e) {
    return pow(t, 1.0 / 3.0);
  } else {
    return (kappa * t + 16) / 116;
  }
}

+ (double)labInvf:(double)ft {
  double e = 216.0 / 24389.0;
  double kappa = 24389.0 / 27.0;
  double ft3 = ft * ft * ft;
  if (ft3 > e) {
    return ft3;
  } else {
    return (116 * ft - 16) / kappa;
  }
}

@end
