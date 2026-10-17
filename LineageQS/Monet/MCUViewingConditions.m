// Port of upstream/aosp-libmonet/hct/ViewingConditions.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUViewingConditions.h"
#import "MCUCam16.h"
#import "MCUColorUtils.h"
#import "MCUMathUtils.h"

@interface MCUViewingConditions ()
- (instancetype)initWithN:(double)n
                       aw:(double)aw
                      nbb:(double)nbb
                      ncb:(double)ncb
                        c:(double)c
                       nc:(double)nc
                     rgbD:(NSArray<NSNumber *> *)rgbD
                       fl:(double)fl
                   flRoot:(double)flRoot
                        z:(double)z;
@end

@implementation MCUViewingConditions {
  double _aw;
  double _nbb;
  double _ncb;
  double _c;
  double _nc;
  double _n;
  NSArray<NSNumber *> *_rgbD;
  double _fl;
  double _flRoot;
  double _z;
}

// Java: public static final ViewingConditions DEFAULT = defaultWithBackgroundLstar(50.0);
+ (MCUViewingConditions *)DEFAULT {
  static MCUViewingConditions *defaultConditions = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaultConditions = [MCUViewingConditions defaultWithBackgroundLstar:50.0];
  });
  return defaultConditions;
}

+ (MCUViewingConditions *)make:(NSArray<NSNumber *> *)whitePoint
             adaptingLuminance:(double)adaptingLuminance
               backgroundLstar:(double)backgroundLstar
                      surround:(double)surround
         discountingIlluminant:(BOOL)discountingIlluminant {
  // A background of pure black is non-physical and leads to infinities that represent the idea
  // that any color viewed in pure black can't be seen.
  backgroundLstar = MCUJavaMax(0.1, backgroundLstar);

  // Transform white point XYZ to 'cone'/'rgb' responses
  const double (*matrix)[3] = MCUCam16XyzToCam16Rgb;
  double xyz0 = MCUVecGet(whitePoint, 0);
  double xyz1 = MCUVecGet(whitePoint, 1);
  double xyz2 = MCUVecGet(whitePoint, 2);
  double rW = (xyz0 * matrix[0][0]) + (xyz1 * matrix[0][1]) + (xyz2 * matrix[0][2]);
  double gW = (xyz0 * matrix[1][0]) + (xyz1 * matrix[1][1]) + (xyz2 * matrix[1][2]);
  double bW = (xyz0 * matrix[2][0]) + (xyz1 * matrix[2][1]) + (xyz2 * matrix[2][2]);

  double f = 0.8 + (surround / 10.0);
  double c = (f >= 0.9) ? [MCUMathUtils lerp:0.59 stop:0.69 amount:((f - 0.9) * 10.0)]
                        : [MCUMathUtils lerp:0.525 stop:0.59 amount:((f - 0.8) * 10.0)];
  double d = discountingIlluminant
                 ? 1.0
                 : f * (1.0 - ((1.0 / 3.6) * exp((-adaptingLuminance - 42.0) / 92.0)));
  d = [MCUMathUtils clampDouble:0.0 max:1.0 input:d];
  double nc = f;
  double rgbD0 = d * (100.0 / rW) + 1.0 - d;
  double rgbD1 = d * (100.0 / gW) + 1.0 - d;
  double rgbD2 = d * (100.0 / bW) + 1.0 - d;
  double k = 1.0 / (5.0 * adaptingLuminance + 1.0);
  double k4 = k * k * k * k;
  double k4F = 1.0 - k4;
  double fl = (k4 * adaptingLuminance) + (0.1 * k4F * k4F * cbrt(5.0 * adaptingLuminance));
  double n = ([MCUColorUtils yFromLstar:backgroundLstar] / MCUVecGet(whitePoint, 1));
  double z = 1.48 + sqrt(n);
  double nbb = 0.725 / pow(n, 0.2);
  double ncb = nbb;
  double rgbAFactors0 = pow(fl * rgbD0 * rW / 100.0, 0.42);
  double rgbAFactors1 = pow(fl * rgbD1 * gW / 100.0, 0.42);
  double rgbAFactors2 = pow(fl * rgbD2 * bW / 100.0, 0.42);
  double rgbA0 = (400.0 * rgbAFactors0) / (rgbAFactors0 + 27.13);
  double rgbA1 = (400.0 * rgbAFactors1) / (rgbAFactors1 + 27.13);
  double rgbA2 = (400.0 * rgbAFactors2) / (rgbAFactors2 + 27.13);
  double aw = ((2.0 * rgbA0) + rgbA1 + (0.05 * rgbA2)) * nbb;
  return [[MCUViewingConditions alloc] initWithN:n
                                              aw:aw
                                             nbb:nbb
                                             ncb:ncb
                                               c:c
                                              nc:nc
                                            rgbD:MCUVec3(rgbD0, rgbD1, rgbD2)
                                              fl:fl
                                           flRoot:pow(fl, 0.25)
                                               z:z];
}

+ (MCUViewingConditions *)defaultWithBackgroundLstar:(double)lstar {
  return [MCUViewingConditions make:[MCUColorUtils whitePointD65]
                  adaptingLuminance:(200.0 / M_PI * [MCUColorUtils yFromLstar:50.0] / 100.0)
                    backgroundLstar:lstar
                           surround:2.0
              discountingIlluminant:NO];
}

/**
 * Parameters are intermediate values of the CAM16 conversion process. Their names are shorthand
 * for technical color science terminology.
 */
- (instancetype)initWithN:(double)n
                       aw:(double)aw
                      nbb:(double)nbb
                      ncb:(double)ncb
                        c:(double)c
                       nc:(double)nc
                     rgbD:(NSArray<NSNumber *> *)rgbD
                       fl:(double)fl
                   flRoot:(double)flRoot
                        z:(double)z {
  self = [super init];
  if (self) {
    _n = n;
    _aw = aw;
    _nbb = nbb;
    _ncb = ncb;
    _c = c;
    _nc = nc;
    _rgbD = rgbD;
    _fl = fl;
    _flRoot = flRoot;
    _z = z;
  }
  return self;
}

- (double)getAw {
  return _aw;
}

- (double)getN {
  return _n;
}

- (double)getNbb {
  return _nbb;
}

- (double)getNcb {
  return _ncb;
}

- (double)getC {
  return _c;
}

- (double)getNc {
  return _nc;
}

- (NSArray<NSNumber *> *)getRgbD {
  return _rgbD;
}

- (double)getFl {
  return _fl;
}

- (double)getFlRoot {
  return _flRoot;
}

- (double)getZ {
  return _z;
}

@end
