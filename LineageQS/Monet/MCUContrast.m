// Port of upstream/aosp-libmonet/contrast/Contrast.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUContrast.h"
#import "MCUColorUtils.h"
#import "MCUMathUtils.h"

// 0.04 selected because it ensures the resulting ratio rounds to the same tenth.
static const double kMCUContrastRatioEpsilon = 0.04;

// 0.4 is generous, ex. HCT requires much less delta. See comment in lighter(tone, ratio).
static const double kMCULuminanceGamutMapTolerance = 0.4;

@implementation MCUContrast

+ (double)RATIO_MIN {
  return 1.0;
}

+ (double)RATIO_MAX {
  return 21.0;
}

+ (double)RATIO_30 {
  return 3.0;
}

+ (double)RATIO_45 {
  return 4.5;
}

+ (double)RATIO_70 {
  return 7.0;
}

+ (double)ratioOfYs:(double)y1 y2:(double)y2 {
  double lighter = MCUJavaMax(y1, y2);
  double darker = (lighter == y2) ? y1 : y2;
  return (lighter + 5.0) / (darker + 5.0);
}

+ (double)ratioOfTones:(double)t1 t2:(double)t2 {
  return [MCUContrast ratioOfYs:[MCUColorUtils yFromLstar:t1] y2:[MCUColorUtils yFromLstar:t2]];
}

+ (double)lighter:(double)tone ratio:(double)ratio {
  if (tone < 0.0 || tone > 100.0) {
    return -1.0;
  }
  // Invert the contrast ratio equation to determine lighter Y given a ratio and darker Y.
  double darkY = [MCUColorUtils yFromLstar:tone];
  double lightY = ratio * (darkY + 5.0) - 5.0;
  if (lightY < 0.0 || lightY > 100.0) {
    return -1.0;
  }
  double realContrast = [MCUContrast ratioOfYs:lightY y2:darkY];
  double delta = fabs(realContrast - ratio);
  if (realContrast < ratio && delta > kMCUContrastRatioEpsilon) {
    return -1.0;
  }

  double returnValue = [MCUColorUtils lstarFromY:lightY] + kMCULuminanceGamutMapTolerance;
  // NOMUTANTS--important validation step; functions it is calling may change implementation.
  if (returnValue < 0 || returnValue > 100) {
    return -1.0;
  }
  return returnValue;
}

+ (double)lighterUnsafe:(double)tone ratio:(double)ratio {
  double lighterSafe = [MCUContrast lighter:tone ratio:ratio];
  return lighterSafe < 0.0 ? 100.0 : lighterSafe;
}

+ (double)darker:(double)tone ratio:(double)ratio {
  if (tone < 0.0 || tone > 100.0) {
    return -1.0;
  }
  // Invert the contrast ratio equation to determine darker Y given a ratio and lighter Y.
  double lightY = [MCUColorUtils yFromLstar:tone];
  double darkY = ((lightY + 5.0) / ratio) - 5.0;
  if (darkY < 0.0 || darkY > 100.0) {
    return -1.0;
  }
  double realContrast = [MCUContrast ratioOfYs:lightY y2:darkY];
  double delta = fabs(realContrast - ratio);
  if (realContrast < ratio && delta > kMCUContrastRatioEpsilon) {
    return -1.0;
  }

  // For information on 0.4 constant, see comment in lighter(tone, ratio).
  double returnValue = [MCUColorUtils lstarFromY:darkY] - kMCULuminanceGamutMapTolerance;
  // NOMUTANTS--important validation step; functions it is calling may change implementation.
  if (returnValue < 0 || returnValue > 100) {
    return -1.0;
  }
  return returnValue;
}

+ (double)darkerUnsafe:(double)tone ratio:(double)ratio {
  double darkerSafe = [MCUContrast darker:tone ratio:ratio];
  return MCUJavaMax(0.0, darkerSafe);
}

@end
