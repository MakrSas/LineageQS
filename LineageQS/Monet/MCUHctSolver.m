// Port of upstream/aosp-libmonet/hct/HctSolver.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUHctSolver.h"
#import "MCUCam16.h"
#import "MCUColorUtils.h"
#import "MCUMathUtils.h"
#import "MCUViewingConditions.h"
#import <stdlib.h>

// Constant tables copied from HctSolver.java.
static const double kMCUScaledDiscountFromLinrgb[3][3] = {
    {0.001200833568784504, 0.002389694492170889, 0.0002795742885861124},
    {0.0005891086651375999, 0.0029785502573438758, 0.0003270666104008398},
    {0.00010146692491640572, 0.0005364214359186694, 0.0032979401770712076},
};
static const double kMCULinrgbFromScaledDiscount[3][3] = {
    {1373.2198709594231, -1100.4251190754821, -7.278681089101213},
    {-271.815969077903, 559.6580465940733, -32.46047482791194},
    {1.9622899599665666, -57.173814538844006, 308.7233197812385},
};
static const double kMCUYFromLinrgb[3] = {
    0.2126, 0.7152, 0.0722,
};
static const double kMCUCriticalPlanes[255] = {
    0.015176349177441876, 0.045529047532325624, 0.07588174588720938,
    0.10623444424209313, 0.13658714259697685, 0.16693984095186062,
    0.19729253930674434, 0.2276452376616281, 0.2579979360165119,
    0.28835063437139563, 0.3188300904430532, 0.350925934958123,
    0.3848314933096426, 0.42057480301049466, 0.458183274052838,
    0.4976837250274023, 0.5391024159806381, 0.5824650784040898,
    0.6277969426914107, 0.6751227633498623, 0.7244668422128921,
    0.775853049866786, 0.829304845476233, 0.8848452951698498,
    0.942497089126609, 1.0022825574869039, 1.0642236851973577,
    1.1283421258858297, 1.1946592148522128, 1.2631959812511864,
    1.3339731595349034, 1.407011200216447, 1.4823302800086415,
    1.5599503113873272, 1.6398909516233677, 1.7221716113234105,
    1.8068114625156377, 1.8938294463134073, 1.9832442801866852,
    2.075074464868551, 2.1693382909216234, 2.2660538449872063,
    2.36523901573795, 2.4669114995532007, 2.5710888059345764,
    2.6777882626779785, 2.7870270208169257, 2.898822059350997,
    3.0131901897720907, 3.1301480604002863, 3.2497121605402226,
    3.3718988244681087, 3.4967242352587946, 3.624204428461639,
    3.754355295633311, 3.887192587735158, 4.022731918402185,
    4.160988767090289, 4.301978482107941, 4.445716283538092,
    4.592217266055746, 4.741496401646282, 4.893568542229298,
    5.048448422192488, 5.20615066083972, 5.3666897647573375,
    5.5300801301023865, 5.696336044816294, 5.865471690767354,
    6.037501145825082, 6.212438385869475, 6.390297286737924,
    6.571091626112461, 6.7548350853498045, 6.941541251256611,
    7.131223617812143, 7.323895587840543, 7.5195704746346665,
    7.7182615035334345, 7.919981813454504, 8.124744458384042,
    8.332562408825165, 8.543448553206703, 8.757415699253682,
    8.974476575321063, 9.194643831691977, 9.417930041841839,
    9.644347703669503, 9.873909240696694, 10.106627003236781,
    10.342513269534024, 10.58158024687427, 10.8238400726681,
    11.069304815507364, 11.317986476196008, 11.569896988756009,
    11.825048221409341, 12.083451977536606, 12.345119996613247,
    12.610063955123938, 12.878295467455942, 13.149826086772048,
    13.42466730586372, 13.702830557985108, 13.984327217668513,
    14.269168601521828, 14.55736596900856, 14.848930523210871,
    15.143873411576273, 15.44220572664832, 15.743938506781891,
    16.04908273684337, 16.35764934889634, 16.66964922287304,
    16.985093187232053, 17.30399201960269, 17.62635644741625,
    17.95219714852476, 18.281524751807332, 18.614349837764564,
    18.95068293910138, 19.290534541298456, 19.633915083172692,
    19.98083495742689, 20.331304511189067, 20.685334046541502,
    21.042933821039977, 21.404114048223256, 21.76888489811322,
    22.137256497705877, 22.50923893145328, 22.884842241736916,
    23.264076429332462, 23.6469514538663, 24.033477234264016,
    24.42366364919083, 24.817520537484558, 25.21505769858089,
    25.61628489293138, 26.021211842414342, 26.429848230738664,
    26.842203703840827, 27.258287870275353, 27.678110301598522,
    28.10168053274597, 28.529008062403893, 28.96010235337422,
    29.39497283293396, 29.83362889318845, 30.276079891419332,
    30.722335150426627, 31.172403958865512, 31.62629557157785,
    32.08401920991837, 32.54558406207592, 33.010999283389665,
    33.4802739966603, 33.953417292456834, 34.430438229418264,
    34.911345834551085, 35.39614910352207, 35.88485700094671,
    36.37747846067349, 36.87402238606382, 37.37449765026789,
    37.87891309649659, 38.38727753828926, 38.89959975977785,
    39.41588851594697, 39.93615253289054, 40.460400508064545,
    40.98864111053629, 41.520882981230194, 42.05713473317016,
    42.597404951718396, 43.141702194811224, 43.6900349931913,
    44.24241185063697, 44.798841244188324, 45.35933162437017,
    45.92389141541209, 46.49252901546552, 47.065252796817916,
    47.64207110610409, 48.22299226451468, 48.808024568002054,
    49.3971762874833, 49.9904556690408, 50.587870934119984,
    51.189430279724725, 51.79514187861014, 52.40501387947288,
    53.0190544071392, 53.637271562750364, 54.259673423945976,
    54.88626804504493, 55.517063457223934, 56.15206766869424,
    56.79128866487574, 57.43473440856916, 58.08241284012621,
    58.734331877617365, 59.39049941699807, 60.05092333227251,
    60.715611475655585, 61.38457167773311, 62.057811747619894,
    62.7353394731159, 63.417162620860914, 64.10328893648692,
    64.79372614476921, 65.48848194977529, 66.18756403501224,
    66.89098006357258, 67.59873767827808, 68.31084450182222,
    69.02730813691093, 69.74813616640164, 70.47333615344107,
    71.20291564160104, 71.93688215501312, 72.67524319850172,
    73.41800625771542, 74.16517879925733, 74.9167682708136,
    75.67278210128072, 76.43322770089146, 77.1981124613393,
    77.96744375590167, 78.74122893956174, 79.51947534912904,
    80.30219030335869, 81.08938110306934, 81.88105503125999,
    82.67721935322541, 83.4778813166706, 84.28304815182372,
    85.09272707154808, 85.90692527145302, 86.72564993000343,
    87.54890820862819, 88.3767072518277, 89.2090541872801,
    90.04595612594655, 90.88742016217518, 91.73345337380438,
    92.58406282226491, 93.43925555268066, 94.29903859396902,
    95.16341895893969, 96.03240364439274, 96.9059996312159,
    97.78421388448044, 98.6670533535366, 99.55452497210776,
};

@implementation MCUHctSolver

+ (double)sanitizeRadians:(double)angle {
  return fmod(angle + M_PI * 8, M_PI * 2);
}

+ (double)trueDelinearized:(double)rgbComponent {
  double normalized = rgbComponent / 100.0;
  double delinearized = 0.0;
  if (normalized <= 0.0031308) {
    delinearized = normalized * 12.92;
  } else {
    delinearized = 1.055 * pow(normalized, 1.0 / 2.4) - 0.055;
  }
  return delinearized * 255.0;
}

+ (double)chromaticAdaptation:(double)component {
  double af = pow(fabs(component), 0.42);
  return [MCUMathUtils signum:component] * 400.0 * af / (af + 27.13);
}

+ (double)hueOf:(NSArray<NSNumber *> *)linrgb {
  NSArray<NSNumber *> *scaledDiscount = [MCUMathUtils matrixMultiply:linrgb matrix:kMCUScaledDiscountFromLinrgb];
  double rA = [MCUHctSolver chromaticAdaptation:MCUVecGet(scaledDiscount, 0)];
  double gA = [MCUHctSolver chromaticAdaptation:MCUVecGet(scaledDiscount, 1)];
  double bA = [MCUHctSolver chromaticAdaptation:MCUVecGet(scaledDiscount, 2)];
  // redness-greenness
  double a = (11.0 * rA + -12.0 * gA + bA) / 11.0;
  // yellowness-blueness
  double b = (rA + gA - 2.0 * bA) / 9.0;
  return atan2(b, a);
}

+ (BOOL)areInCyclicOrder:(double)a b:(double)b c:(double)c {
  double deltaAB = [MCUHctSolver sanitizeRadians:b - a];
  double deltaAC = [MCUHctSolver sanitizeRadians:c - a];
  return deltaAB < deltaAC;
}

+ (double)intercept:(double)source mid:(double)mid target:(double)target {
  return (mid - source) / (target - source);
}

+ (NSArray<NSNumber *> *)lerpPoint:(NSArray<NSNumber *> *)source
                                 t:(double)t
                            target:(NSArray<NSNumber *> *)target {
  double s0 = MCUVecGet(source, 0);
  double s1 = MCUVecGet(source, 1);
  double s2 = MCUVecGet(source, 2);
  double t0 = MCUVecGet(target, 0);
  double t1 = MCUVecGet(target, 1);
  double t2 = MCUVecGet(target, 2);
  return MCUVec3(s0 + (t0 - s0) * t,
                 s1 + (t1 - s1) * t,
                 s2 + (t2 - s2) * t);
}

+ (NSArray<NSNumber *> *)setCoordinate:(NSArray<NSNumber *> *)source
                            coordinate:(double)coordinate
                                target:(NSArray<NSNumber *> *)target
                                  axis:(int)axis {
  double t = [MCUHctSolver intercept:MCUVecGet(source, axis)
                                 mid:coordinate
                              target:MCUVecGet(target, axis)];
  return [MCUHctSolver lerpPoint:source t:t target:target];
}

+ (BOOL)isBounded:(double)x {
  return 0.0 <= x && x <= 100.0;
}

+ (NSArray<NSNumber *> *)nthVertex:(double)y n:(int)n {
  double kR = kMCUYFromLinrgb[0];
  double kG = kMCUYFromLinrgb[1];
  double kB = kMCUYFromLinrgb[2];
  double coordA = n % 4 <= 1 ? 0.0 : 100.0;
  double coordB = n % 2 == 0 ? 0.0 : 100.0;
  if (n < 4) {
    double g = coordA;
    double b = coordB;
    double r = (y - g * kG - b * kB) / kR;
    if ([MCUHctSolver isBounded:r]) {
      return MCUVec3(r, g, b);
    } else {
      return MCUVec3(-1.0, -1.0, -1.0);
    }
  } else if (n < 8) {
    double b = coordA;
    double r = coordB;
    double g = (y - r * kR - b * kB) / kG;
    if ([MCUHctSolver isBounded:g]) {
      return MCUVec3(r, g, b);
    } else {
      return MCUVec3(-1.0, -1.0, -1.0);
    }
  } else {
    double r = coordA;
    double g = coordB;
    double b = (y - r * kR - g * kG) / kB;
    if ([MCUHctSolver isBounded:b]) {
      return MCUVec3(r, g, b);
    } else {
      return MCUVec3(-1.0, -1.0, -1.0);
    }
  }
}

+ (NSArray<NSArray<NSNumber *> *> *)bisectToSegment:(double)y targetHue:(double)targetHue {
  NSArray<NSNumber *> *left = MCUVec3(-1.0, -1.0, -1.0);
  NSArray<NSNumber *> *right = left;
  double leftHue = 0.0;
  double rightHue = 0.0;
  BOOL initialized = NO;
  BOOL uncut = YES;
  for (int n = 0; n < 12; n++) {
    NSArray<NSNumber *> *mid = [MCUHctSolver nthVertex:y n:n];
    if (MCUVecGet(mid, 0) < 0) {
      continue;
    }
    double midHue = [MCUHctSolver hueOf:mid];
    if (!initialized) {
      left = mid;
      right = mid;
      leftHue = midHue;
      rightHue = midHue;
      initialized = YES;
      continue;
    }
    if (uncut || [MCUHctSolver areInCyclicOrder:leftHue b:midHue c:rightHue]) {
      uncut = NO;
      if ([MCUHctSolver areInCyclicOrder:leftHue b:targetHue c:midHue]) {
        right = mid;
        rightHue = midHue;
      } else {
        left = mid;
        leftHue = midHue;
      }
    }
  }
  return @[left, right];
}

+ (NSArray<NSNumber *> *)midpoint:(NSArray<NSNumber *> *)a b:(NSArray<NSNumber *> *)b {
  return MCUVec3((MCUVecGet(a, 0) + MCUVecGet(b, 0)) / 2,
                 (MCUVecGet(a, 1) + MCUVecGet(b, 1)) / 2,
                 (MCUVecGet(a, 2) + MCUVecGet(b, 2)) / 2);
}

+ (int)criticalPlaneBelow:(double)x {
  return MCUJavaD2I(floor(x - 0.5));
}

+ (int)criticalPlaneAbove:(double)x {
  return MCUJavaD2I(ceil(x - 0.5));
}

+ (NSArray<NSNumber *> *)bisectToLimit:(double)y targetHue:(double)targetHue {
  NSArray<NSArray<NSNumber *> *> *segment = [MCUHctSolver bisectToSegment:y targetHue:targetHue];
  NSArray<NSNumber *> *left = segment[0];
  double leftHue = [MCUHctSolver hueOf:left];
  NSArray<NSNumber *> *right = segment[1];
  for (int axis = 0; axis < 3; axis++) {
    if (MCUVecGet(left, axis) != MCUVecGet(right, axis)) {
      int lPlane = -1;
      int rPlane = 255;
      if (MCUVecGet(left, axis) < MCUVecGet(right, axis)) {
        lPlane = [MCUHctSolver criticalPlaneBelow:[MCUHctSolver trueDelinearized:MCUVecGet(left, axis)]];
        rPlane = [MCUHctSolver criticalPlaneAbove:[MCUHctSolver trueDelinearized:MCUVecGet(right, axis)]];
      } else {
        lPlane = [MCUHctSolver criticalPlaneAbove:[MCUHctSolver trueDelinearized:MCUVecGet(left, axis)]];
        rPlane = [MCUHctSolver criticalPlaneBelow:[MCUHctSolver trueDelinearized:MCUVecGet(right, axis)]];
      }
      for (int i = 0; i < 8; i++) {
        if (abs(rPlane - lPlane) <= 1) {
          break;
        } else {
          int mPlane = MCUJavaD2I(floor((lPlane + rPlane) / 2.0));
          double midPlaneCoordinate = kMCUCriticalPlanes[mPlane];
          NSArray<NSNumber *> *mid = [MCUHctSolver setCoordinate:left
                                                      coordinate:midPlaneCoordinate
                                                          target:right
                                                            axis:axis];
          double midHue = [MCUHctSolver hueOf:mid];
          if ([MCUHctSolver areInCyclicOrder:leftHue b:targetHue c:midHue]) {
            right = mid;
            rPlane = mPlane;
          } else {
            left = mid;
            leftHue = midHue;
            lPlane = mPlane;
          }
        }
      }
    }
  }
  return [MCUHctSolver midpoint:left b:right];
}

+ (double)inverseChromaticAdaptation:(double)adapted {
  double adaptedAbs = fabs(adapted);
  double base = MCUJavaMax(0, 27.13 * adaptedAbs / (400.0 - adaptedAbs));
  return [MCUMathUtils signum:adapted] * pow(base, 1.0 / 0.42);
}

+ (int)findResultByJ:(double)hueRadians chroma:(double)chroma y:(double)y {
  // Initial estimate of j.
  double j = sqrt(y) * 11.0;

  // ===========================================================
  // Operations inlined from Cam16 to avoid repeated calculation
  // ===========================================================
  MCUViewingConditions *viewingConditions = [MCUViewingConditions DEFAULT];
  double tInnerCoeff = 1 / pow(1.64 - pow(0.29, [viewingConditions getN]), 0.73);
  double eHue = 0.25 * (cos(hueRadians + 2.0) + 3.8);
  double p1 = eHue * (50000.0 / 13.0) * [viewingConditions getNc] * [viewingConditions getNcb];
  double hSin = sin(hueRadians);
  double hCos = cos(hueRadians);
  for (int iterationRound = 0; iterationRound < 5; iterationRound++) {
    // ===========================================================
    // Operations inlined from Cam16 to avoid repeated calculation
    // ===========================================================
    double jNormalized = j / 100.0;
    double alpha = (chroma == 0.0 || j == 0.0) ? 0.0 : chroma / sqrt(jNormalized);
    double t = pow(alpha * tInnerCoeff, 1.0 / 0.9);
    double ac = [viewingConditions getAw] *
                pow(jNormalized, 1.0 / [viewingConditions getC] / [viewingConditions getZ]);
    double p2 = ac / [viewingConditions getNbb];
    double gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11 * t * hCos + 108.0 * t * hSin);
    double a = gamma * hCos;
    double b = gamma * hSin;
    double rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
    double gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
    double bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;
    double rCScaled = [MCUHctSolver inverseChromaticAdaptation:rA];
    double gCScaled = [MCUHctSolver inverseChromaticAdaptation:gA];
    double bCScaled = [MCUHctSolver inverseChromaticAdaptation:bA];
    NSArray<NSNumber *> *linrgb = [MCUMathUtils matrixMultiply:MCUVec3(rCScaled, gCScaled, bCScaled)
                                                        matrix:kMCULinrgbFromScaledDiscount];

    // ===========================================================
    // Operations inlined from Cam16 to avoid repeated calculation
    // ===========================================================
    if (MCUVecGet(linrgb, 0) < 0 || MCUVecGet(linrgb, 1) < 0 || MCUVecGet(linrgb, 2) < 0) {
      return 0;
    }
    double kR = kMCUYFromLinrgb[0];
    double kG = kMCUYFromLinrgb[1];
    double kB = kMCUYFromLinrgb[2];
    double fnj = kR * MCUVecGet(linrgb, 0) + kG * MCUVecGet(linrgb, 1) + kB * MCUVecGet(linrgb, 2);
    if (fnj <= 0) {
      return 0;
    }
    if (iterationRound == 4 || fabs(fnj - y) < 0.002) {
      if (MCUVecGet(linrgb, 0) > 100.01 || MCUVecGet(linrgb, 1) > 100.01 ||
          MCUVecGet(linrgb, 2) > 100.01) {
        return 0;
      }
      return [MCUColorUtils argbFromLinrgb:linrgb];
    }
    // Iterates with Newton method,
    // Using 2 * fn(j) / j as the approximation of fn'(j)
    j = j - (fnj - y) * j / (2 * fnj);
  }
  return 0;
}

+ (int)solveToInt:(double)hueDegrees chroma:(double)chroma lstar:(double)lstar {
  if (chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999) {
    return [MCUColorUtils argbFromLstar:lstar];
  }
  hueDegrees = [MCUMathUtils sanitizeDegreesDouble:hueDegrees];
  double hueRadians = hueDegrees / 180 * M_PI;
  double y = [MCUColorUtils yFromLstar:lstar];
  int exactAnswer = [MCUHctSolver findResultByJ:hueRadians chroma:chroma y:y];
  if (exactAnswer != 0) {
    return exactAnswer;
  }
  NSArray<NSNumber *> *linrgb = [MCUHctSolver bisectToLimit:y targetHue:hueRadians];
  return [MCUColorUtils argbFromLinrgb:linrgb];
}

+ (MCUCam16 *)solveToCam:(double)hueDegrees chroma:(double)chroma lstar:(double)lstar {
  return [MCUCam16 fromInt:[MCUHctSolver solveToInt:hueDegrees chroma:chroma lstar:lstar]];
}

@end
