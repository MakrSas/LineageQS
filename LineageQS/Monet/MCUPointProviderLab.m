// Port of upstream/aosp-libmonet/quantize/PointProviderLab.java (libmonet, Apache License 2.0, Copyright Google LLC).

#import "MCUPointProviderLab.h"
#import "MCUColorUtils.h"

@implementation MCUPointProviderLab

- (void)fromInt:(int)argb out:(double *)out {
  NSArray<NSNumber *> *lab = [MCUColorUtils labFromArgb:argb];
  out[0] = [lab[0] doubleValue];
  out[1] = [lab[1] doubleValue];
  out[2] = [lab[2] doubleValue];
}

- (int)toInt:(const double *)lab {
  return [MCUColorUtils argbFromLab:lab[0] a:lab[1] b:lab[2]];
}

- (double)distance:(const double *)one b:(const double *)two {
  double dL = (one[0] - two[0]);
  double dA = (one[1] - two[1]);
  double dB = (one[2] - two[2]);
  return (dL * dL + dA * dA + dB * dB);
}

@end
