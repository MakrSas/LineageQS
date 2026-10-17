// Port of upstream/aosp-libmonet/hct/Cam16.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUCam16.h"
#import "MCUColorUtils.h"
#import "MCUMathUtils.h"

// Transforms XYZ color space coordinates to 'cone'/'RGB' responses in CAM16 (declared in MCUCam16.h).
const double MCUCam16XyzToCam16Rgb[3][3] = {
    {0.401288, 0.650173, -0.051461},
    {-0.250268, 1.204414, 0.045854},
    {-0.002079, 0.048952, 0.953127},
};

// Transforms 'cone'/'RGB' responses in CAM16 to XYZ color space coordinates.
static const double kMCUCam16RgbToXyz[3][3] = {
    {1.8620678, -1.0112547, 0.14918678},
    {0.38752654, 0.62144744, -0.00897398},
    {-0.01584150, -0.03412294, 1.0499644},
};

@interface MCUCam16 ()
- (instancetype)initWithHue:(double)hue
                     chroma:(double)chroma
                          j:(double)j
                          q:(double)q
                          m:(double)m
                          s:(double)s
                      jstar:(double)jstar
                      astar:(double)astar
                      bstar:(double)bstar;
+ (MCUCam16 *)fromJchInViewingConditions:(double)j
                                       c:(double)c
                                       h:(double)h
                       viewingConditions:(MCUViewingConditions *)viewingConditions;
@end

@implementation MCUCam16 {
  // CAM16 color dimensions, see getters for documentation.
  double _hue;
  double _chroma;
  double _j;
  double _q;
  double _m;
  double _s;

  // Coordinates in UCS space. Used to determine color distance, like delta E equations in L*a*b*.
  double _jstar;
  double _astar;
  double _bstar;

  // Avoid allocations during conversion by pre-allocating an array.
  NSMutableArray<NSNumber *> *_tempArray;
}

- (instancetype)initWithHue:(double)hue
                     chroma:(double)chroma
                          j:(double)j
                          q:(double)q
                          m:(double)m
                          s:(double)s
                      jstar:(double)jstar
                      astar:(double)astar
                      bstar:(double)bstar {
  self = [super init];
  if (self) {
    _tempArray = [NSMutableArray arrayWithObjects:@0.0, @0.0, @0.0, nil];
    _hue = hue;
    _chroma = chroma;
    _j = j;
    _q = q;
    _m = m;
    _s = s;
    _jstar = jstar;
    _astar = astar;
    _bstar = bstar;
  }
  return self;
}

- (double)distance:(MCUCam16 *)other {
  double dJ = [self getJstar] - [other getJstar];
  double dA = [self getAstar] - [other getAstar];
  double dB = [self getBstar] - [other getBstar];
  double dEPrime = sqrt(dJ * dJ + dA * dA + dB * dB);
  double dE = 1.41 * pow(dEPrime, 0.63);
  return dE;
}

- (double)getHue {
  return _hue;
}

- (double)getChroma {
  return _chroma;
}

- (double)getJ {
  return _j;
}

- (double)getQ {
  return _q;
}

- (double)getM {
  return _m;
}

- (double)getS {
  return _s;
}

- (double)getJstar {
  return _jstar;
}

- (double)getAstar {
  return _astar;
}

- (double)getBstar {
  return _bstar;
}

+ (MCUCam16 *)fromInt:(int)argb {
  return [MCUCam16 fromIntInViewingConditions:argb viewingConditions:[MCUViewingConditions DEFAULT]];
}

+ (MCUCam16 *)fromIntInViewingConditions:(int)argb viewingConditions:(MCUViewingConditions *)viewingConditions {
  // Transform ARGB int to XYZ
  int red = (argb & 0x00ff0000) >> 16;
  int green = (argb & 0x0000ff00) >> 8;
  int blue = (argb & 0x000000ff);
  double redL = [MCUColorUtils linearized:red];
  double greenL = [MCUColorUtils linearized:green];
  double blueL = [MCUColorUtils linearized:blue];
  double x = 0.41233895 * redL + 0.35762064 * greenL + 0.18051042 * blueL;
  double y = 0.2126 * redL + 0.7152 * greenL + 0.0722 * blueL;
  double z = 0.01932141 * redL + 0.11916382 * greenL + 0.95034478 * blueL;

  return [MCUCam16 fromXyzInViewingConditions:x y:y z:z viewingConditions:viewingConditions];
}

+ (MCUCam16 *)fromXyzInViewingConditions:(double)x
                                       y:(double)y
                                       z:(double)z
                       viewingConditions:(MCUViewingConditions *)viewingConditions {
  // Transform XYZ to 'cone'/'rgb' responses
  const double (*matrix)[3] = MCUCam16XyzToCam16Rgb;
  double rT = (x * matrix[0][0]) + (y * matrix[0][1]) + (z * matrix[0][2]);
  double gT = (x * matrix[1][0]) + (y * matrix[1][1]) + (z * matrix[1][2]);
  double bT = (x * matrix[2][0]) + (y * matrix[2][1]) + (z * matrix[2][2]);

  // Discount illuminant
  double rD = MCUVecGet([viewingConditions getRgbD], 0) * rT;
  double gD = MCUVecGet([viewingConditions getRgbD], 1) * gT;
  double bD = MCUVecGet([viewingConditions getRgbD], 2) * bT;

  // Chromatic adaptation
  double rAF = pow([viewingConditions getFl] * fabs(rD) / 100.0, 0.42);
  double gAF = pow([viewingConditions getFl] * fabs(gD) / 100.0, 0.42);
  double bAF = pow([viewingConditions getFl] * fabs(bD) / 100.0, 0.42);
  double rA = MCUJavaSignum(rD) * 400.0 * rAF / (rAF + 27.13);
  double gA = MCUJavaSignum(gD) * 400.0 * gAF / (gAF + 27.13);
  double bA = MCUJavaSignum(bD) * 400.0 * bAF / (bAF + 27.13);

  // redness-greenness
  double a = (11.0 * rA + -12.0 * gA + bA) / 11.0;
  // yellowness-blueness
  double b = (rA + gA - 2.0 * bA) / 9.0;

  // auxiliary components
  double u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0;
  double p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0;

  // hue
  double atan2Value = atan2(b, a);
  double atanDegrees = MCUJavaToDegrees(atan2Value);
  double hue = [MCUMathUtils sanitizeDegreesDouble:atanDegrees];
  double hueRadians = MCUJavaToRadians(hue);

  // achromatic response to color
  double ac = p2 * [viewingConditions getNbb];

  // CAM16 lightness and brightness
  double j = 100.0 * pow(ac / [viewingConditions getAw],
                         [viewingConditions getC] * [viewingConditions getZ]);
  double q = 4.0 / [viewingConditions getC] * sqrt(j / 100.0) * ([viewingConditions getAw] + 4.0) *
             [viewingConditions getFlRoot];

  // CAM16 chroma, colorfulness, and saturation.
  double huePrime = (hue < 20.14) ? hue + 360 : hue;
  double eHue = 0.25 * (cos(MCUJavaToRadians(huePrime) + 2.0) + 3.8);
  double p1 = 50000.0 / 13.0 * eHue * [viewingConditions getNc] * [viewingConditions getNcb];
  double t = p1 * hypot(a, b) / (u + 0.305);
  double alpha = pow(1.64 - pow(0.29, [viewingConditions getN]), 0.73) * pow(t, 0.9);
  // CAM16 chroma, colorfulness, saturation
  double c = alpha * sqrt(j / 100.0);
  double m = c * [viewingConditions getFlRoot];
  double s = 50.0 * sqrt((alpha * [viewingConditions getC]) / ([viewingConditions getAw] + 4.0));

  // CAM16-UCS components
  double jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j);
  double mstar = 1.0 / 0.0228 * log1p(0.0228 * m);
  double astar = mstar * cos(hueRadians);
  double bstar = mstar * sin(hueRadians);

  return [[MCUCam16 alloc] initWithHue:hue chroma:c j:j q:q m:m s:s jstar:jstar astar:astar bstar:bstar];
}

+ (MCUCam16 *)fromJch:(double)j c:(double)c h:(double)h {
  return [MCUCam16 fromJchInViewingConditions:j c:c h:h viewingConditions:[MCUViewingConditions DEFAULT]];
}

+ (MCUCam16 *)fromJchInViewingConditions:(double)j
                                       c:(double)c
                                       h:(double)h
                       viewingConditions:(MCUViewingConditions *)viewingConditions {
  double q = 4.0 / [viewingConditions getC] * sqrt(j / 100.0) * ([viewingConditions getAw] + 4.0) *
             [viewingConditions getFlRoot];
  double m = c * [viewingConditions getFlRoot];
  double alpha = c / sqrt(j / 100.0);
  double s = 50.0 * sqrt((alpha * [viewingConditions getC]) / ([viewingConditions getAw] + 4.0));

  double hueRadians = MCUJavaToRadians(h);
  double jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j);
  double mstar = 1.0 / 0.0228 * log1p(0.0228 * m);
  double astar = mstar * cos(hueRadians);
  double bstar = mstar * sin(hueRadians);
  return [[MCUCam16 alloc] initWithHue:h chroma:c j:j q:q m:m s:s jstar:jstar astar:astar bstar:bstar];
}

+ (MCUCam16 *)fromUcs:(double)jstar astar:(double)astar bstar:(double)bstar {
  return [MCUCam16 fromUcsInViewingConditions:jstar
                                        astar:astar
                                        bstar:bstar
                            viewingConditions:[MCUViewingConditions DEFAULT]];
}

+ (MCUCam16 *)fromUcsInViewingConditions:(double)jstar
                                   astar:(double)astar
                                   bstar:(double)bstar
                       viewingConditions:(MCUViewingConditions *)viewingConditions {
  double m = hypot(astar, bstar);
  double m2 = expm1(m * 0.0228) / 0.0228;
  double c = m2 / [viewingConditions getFlRoot];
  double h = atan2(bstar, astar) * (180.0 / M_PI);
  if (h < 0.0) {
    h += 360.0;
  }
  double j = jstar / (1. - (jstar - 100.) * 0.007);
  return [MCUCam16 fromJchInViewingConditions:j c:c h:h viewingConditions:viewingConditions];
}

- (int)toInt {
  return [self viewed:[MCUViewingConditions DEFAULT]];
}

- (int)viewed:(MCUViewingConditions *)viewingConditions {
  NSArray<NSNumber *> *xyz = [self xyzInViewingConditions:viewingConditions returnArray:_tempArray];
  return [MCUColorUtils argbFromXyz:MCUVecGet(xyz, 0) y:MCUVecGet(xyz, 1) z:MCUVecGet(xyz, 2)];
}

- (NSArray<NSNumber *> *)xyzInViewingConditions:(MCUViewingConditions *)viewingConditions
                                    returnArray:(nullable NSMutableArray<NSNumber *> *)returnArray {
  double alpha = ([self getChroma] == 0.0 || [self getJ] == 0.0)
                     ? 0.0
                     : [self getChroma] / sqrt([self getJ] / 100.0);

  double t = pow(alpha / pow(1.64 - pow(0.29, [viewingConditions getN]), 0.73), 1.0 / 0.9);
  double hRad = MCUJavaToRadians([self getHue]);

  double eHue = 0.25 * (cos(hRad + 2.0) + 3.8);
  double ac = [viewingConditions getAw] *
              pow([self getJ] / 100.0, 1.0 / [viewingConditions getC] / [viewingConditions getZ]);
  double p1 = eHue * (50000.0 / 13.0) * [viewingConditions getNc] * [viewingConditions getNcb];
  double p2 = (ac / [viewingConditions getNbb]);

  double hSin = sin(hRad);
  double hCos = cos(hRad);

  double gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin);
  double a = gamma * hCos;
  double b = gamma * hSin;
  double rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
  double gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
  double bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;

  double rCBase = MCUJavaMax(0, (27.13 * fabs(rA)) / (400.0 - fabs(rA)));
  double rC = MCUJavaSignum(rA) * (100.0 / [viewingConditions getFl]) * pow(rCBase, 1.0 / 0.42);
  double gCBase = MCUJavaMax(0, (27.13 * fabs(gA)) / (400.0 - fabs(gA)));
  double gC = MCUJavaSignum(gA) * (100.0 / [viewingConditions getFl]) * pow(gCBase, 1.0 / 0.42);
  double bCBase = MCUJavaMax(0, (27.13 * fabs(bA)) / (400.0 - fabs(bA)));
  double bC = MCUJavaSignum(bA) * (100.0 / [viewingConditions getFl]) * pow(bCBase, 1.0 / 0.42);
  double rF = rC / MCUVecGet([viewingConditions getRgbD], 0);
  double gF = gC / MCUVecGet([viewingConditions getRgbD], 1);
  double bF = bC / MCUVecGet([viewingConditions getRgbD], 2);

  const double (*matrix)[3] = kMCUCam16RgbToXyz;
  double x = (rF * matrix[0][0]) + (gF * matrix[0][1]) + (bF * matrix[0][2]);
  double y = (rF * matrix[1][0]) + (gF * matrix[1][1]) + (bF * matrix[1][2]);
  double z = (rF * matrix[2][0]) + (gF * matrix[2][1]) + (bF * matrix[2][2]);

  if (returnArray != nil) {
    [returnArray removeAllObjects];
    [returnArray addObject:@(x)];
    [returnArray addObject:@(y)];
    [returnArray addObject:@(z)];
    return returnArray;
  } else {
    return MCUVec3(x, y, z);
  }
}

@end
