// Port of upstream/aosp-libmonet/temperature/TemperatureCache.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUTemperatureCache.h"
#import "MCUColorUtils.h"
#import "MCUHct.h"
#import "MCUMathUtils.h"
#import <stdlib.h>

@interface MCUTemperatureCache ()
- (MCUHct *)getColdest;
- (NSArray<MCUHct *> *)getHctsByHue;
- (NSArray<MCUHct *> *)getHctsByTemp;
- (NSMapTable<MCUHct *, NSNumber *> *)getTempsByHct;
- (MCUHct *)getWarmest;
+ (BOOL)isBetween:(double)angle a:(double)a b:(double)b;
@end

@implementation MCUTemperatureCache {
  // Color to find complement/analogous colors of.
  MCUHct *_input;

  MCUHct *_precomputedComplement;
  NSArray<MCUHct *> *_precomputedHctsByTemp;
  NSArray<MCUHct *> *_precomputedHctsByHue;
  // Keys are HCTs by object identity (MCUHct does not override isEqual:/hash), values raw temperature.
  NSMapTable<MCUHct *, NSNumber *> *_precomputedTempsByHct;
}

- (instancetype)initWithInput:(MCUHct *)input {
  self = [super init];
  if (self) {
    _input = input;
  }
  return self;
}

- (MCUHct *)getComplement {
  if (_precomputedComplement != nil) {
    return _precomputedComplement;
  }

  double coldestHue = [[self getColdest] getHue];
  double coldestTemp = [[[self getTempsByHct] objectForKey:[self getColdest]] doubleValue];

  double warmestHue = [[self getWarmest] getHue];
  double warmestTemp = [[[self getTempsByHct] objectForKey:[self getWarmest]] doubleValue];
  double range = warmestTemp - coldestTemp;
  BOOL startHueIsColdestToWarmest = [MCUTemperatureCache isBetween:[_input getHue] a:coldestHue b:warmestHue];
  double startHue = startHueIsColdestToWarmest ? warmestHue : coldestHue;
  double endHue = startHueIsColdestToWarmest ? coldestHue : warmestHue;
  double directionOfRotation = 1.;
  double smallestError = 1000.;
  MCUHct *answer = [self getHctsByHue][(NSUInteger)(int)MCUJavaRound([_input getHue])];

  double complementRelativeTemp = (1. - [self getRelativeTemperature:_input]);
  // Find the color in the other section, closest to the inverse percentile
  // of the input color. This is the complement.
  for (double hueAddend = 0.; hueAddend <= 360.; hueAddend += 1.) {
    double hue = [MCUMathUtils sanitizeDegreesDouble:startHue + directionOfRotation * hueAddend];
    if (![MCUTemperatureCache isBetween:hue a:startHue b:endHue]) {
      continue;
    }
    MCUHct *possibleAnswer = [self getHctsByHue][(NSUInteger)(int)MCUJavaRound(hue)];
    double relativeTemp = ([[[self getTempsByHct] objectForKey:possibleAnswer] doubleValue] - coldestTemp) / range;
    double error = fabs(complementRelativeTemp - relativeTemp);
    if (error < smallestError) {
      smallestError = error;
      answer = possibleAnswer;
    }
  }
  _precomputedComplement = answer;
  return _precomputedComplement;
}

- (NSArray<MCUHct *> *)getAnalogousColors {
  return [self getAnalogousColors:5 divisions:12];
}

- (NSArray<MCUHct *> *)getAnalogousColors:(int)count divisions:(int)divisions {
  NSArray<MCUHct *> *hues = [self getHctsByHue];

  // The starting hue is the hue of the input color.
  int startHue = (int)MCUJavaRound([_input getHue]);
  MCUHct *startHct = hues[(NSUInteger)startHue];
  double lastTemp = [self getRelativeTemperature:startHct];

  NSMutableArray<MCUHct *> *allColors = [NSMutableArray array];
  [allColors addObject:startHct];

  double absoluteTotalTempDelta = 0.f;
  for (int i = 0; i < 360; i++) {
    int hue = [MCUMathUtils sanitizeDegreesInt:startHue + i];
    MCUHct *hct = hues[(NSUInteger)hue];
    double temp = [self getRelativeTemperature:hct];
    double tempDelta = fabs(temp - lastTemp);
    lastTemp = temp;
    absoluteTotalTempDelta += tempDelta;
  }

  int hueAddend = 1;
  double tempStep = absoluteTotalTempDelta / (double)divisions;
  double totalTempDelta = 0.0;
  lastTemp = [self getRelativeTemperature:startHct];
  while ((int)allColors.count < divisions) {
    int hue = [MCUMathUtils sanitizeDegreesInt:startHue + hueAddend];
    MCUHct *hct = hues[(NSUInteger)hue];
    double temp = [self getRelativeTemperature:hct];
    double tempDelta = fabs(temp - lastTemp);
    totalTempDelta += tempDelta;

    double desiredTotalTempDeltaForIndex = ((double)allColors.count * tempStep);
    BOOL indexSatisfied = totalTempDelta >= desiredTotalTempDeltaForIndex;
    int indexAddend = 1;
    // Keep adding this hue to the answers until its temperature is
    // insufficient. This ensures consistent behavior when there aren't
    // `divisions` discrete steps between 0 and 360 in hue with `tempStep`
    // delta in temperature between them.
    //
    // For example, white and black have no analogues: there are no other
    // colors at T100/T0. Therefore, they should just be added to the array
    // as answers.
    while (indexSatisfied && (int)allColors.count < divisions) {
      [allColors addObject:hct];
      desiredTotalTempDeltaForIndex = ((double)((int)allColors.count + indexAddend) * tempStep);
      indexSatisfied = totalTempDelta >= desiredTotalTempDeltaForIndex;
      indexAddend++;
    }
    lastTemp = temp;
    hueAddend++;

    if (hueAddend > 360) {
      while ((int)allColors.count < divisions) {
        [allColors addObject:hct];
      }
      break;
    }
  }

  NSMutableArray<MCUHct *> *answers = [NSMutableArray array];
  [answers addObject:_input];

  int ccwCount = MCUJavaD2I(floor(((double)count - 1.0) / 2.0));
  for (int i = 1; i < (ccwCount + 1); i++) {
    int index = 0 - i;
    while (index < 0) {
      index = (int)allColors.count + index;
    }
    if (index >= (int)allColors.count) {
      index = index % (int)allColors.count;
    }
    [answers insertObject:allColors[(NSUInteger)index] atIndex:0];
  }

  int cwCount = count - ccwCount - 1;
  for (int i = 1; i < (cwCount + 1); i++) {
    int index = i;
    while (index < 0) {
      index = (int)allColors.count + index;
    }
    if (index >= (int)allColors.count) {
      index = index % (int)allColors.count;
    }
    [answers addObject:allColors[(NSUInteger)index]];
  }

  return answers;
}

- (double)getRelativeTemperature:(MCUHct *)hct {
  NSMapTable<MCUHct *, NSNumber *> *temps = [self getTempsByHct];
  double range = [[temps objectForKey:[self getWarmest]] doubleValue] - [[temps objectForKey:[self getColdest]] doubleValue];
  double differenceFromColdest = [[temps objectForKey:hct] doubleValue] - [[temps objectForKey:[self getColdest]] doubleValue];
  // Handle when there's no difference in temperature between warmest and
  // coldest: for example, at T100, only one color is available, white.
  if (range == 0.) {
    return 0.5;
  }
  return differenceFromColdest / range;
}

+ (double)rawTemperature:(MCUHct *)color {
  NSArray<NSNumber *> *lab = [MCUColorUtils labFromArgb:[color toInt]];
  double hue = [MCUMathUtils sanitizeDegreesDouble:MCUJavaToDegrees(atan2(MCUVecGet(lab, 2), MCUVecGet(lab, 1)))];
  double chroma = hypot(MCUVecGet(lab, 1), MCUVecGet(lab, 2));
  return -0.5 + 0.02 * pow(chroma, 1.07) *
                    cos(MCUJavaToRadians([MCUMathUtils sanitizeDegreesDouble:hue - 50.]));
}

/** Coldest color with same chroma and tone as input. */
- (MCUHct *)getColdest {
  return [self getHctsByTemp][0];
}

/**
 * HCTs for all colors with the same chroma/tone as the input.
 * Sorted by hue, ex. index 0 is hue 0.
 */
- (NSArray<MCUHct *> *)getHctsByHue {
  if (_precomputedHctsByHue != nil) {
    return _precomputedHctsByHue;
  }
  NSMutableArray<MCUHct *> *hcts = [NSMutableArray array];
  for (double hue = 0.; hue <= 360.; hue += 1.) {
    MCUHct *colorAtHue = [MCUHct from:hue chroma:[_input getChroma] tone:[_input getTone]];
    [hcts addObject:colorAtHue];
  }
  _precomputedHctsByHue = [hcts copy];
  return _precomputedHctsByHue;
}

/**
 * HCTs for all colors with the same chroma/tone as the input.
 * Sorted from coldest first to warmest last.
 */
- (NSArray<MCUHct *> *)getHctsByTemp {
  if (_precomputedHctsByTemp != nil) {
    return _precomputedHctsByTemp;
  }

  NSMutableArray<MCUHct *> *hcts = [NSMutableArray arrayWithArray:[self getHctsByHue]];
  [hcts addObject:_input];
  NSMapTable<MCUHct *, NSNumber *> *temps = [self getTempsByHct];
  // Stable sort by raw temperature, using Double.compare ordering (as Java Collections.sort).
  _precomputedHctsByTemp = [hcts sortedArrayWithOptions:NSSortStable
                                        usingComparator:^NSComparisonResult(MCUHct *a, MCUHct *b) {
                                          int c = MCUJavaDoubleCompare([[temps objectForKey:a] doubleValue],
                                                                       [[temps objectForKey:b] doubleValue]);
                                          if (c < 0) {
                                            return NSOrderedAscending;
                                          }
                                          if (c > 0) {
                                            return NSOrderedDescending;
                                          }
                                          return NSOrderedSame;
                                        }];
  return _precomputedHctsByTemp;
}

/** Keys of HCTs in getHctsByTemp, values of raw temperature. */
- (NSMapTable<MCUHct *, NSNumber *> *)getTempsByHct {
  if (_precomputedTempsByHct != nil) {
    return _precomputedTempsByHct;
  }

  NSMutableArray<MCUHct *> *allHcts = [NSMutableArray arrayWithArray:[self getHctsByHue]];
  [allHcts addObject:_input];

  // Java HashMap<Hct, Double> with Hct keyed by identity (no equals/hashCode override). NSMapTable
  // with object-pointer personality gives the same identity keys without copying them.
  NSMapTable<MCUHct *, NSNumber *> *temperaturesByHct =
      [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality |
                                         NSPointerFunctionsStrongMemory
                            valueOptions:NSPointerFunctionsStrongMemory];
  for (MCUHct *hct in allHcts) {
    [temperaturesByHct setObject:@([MCUTemperatureCache rawTemperature:hct]) forKey:hct];
  }

  _precomputedTempsByHct = temperaturesByHct;
  return _precomputedTempsByHct;
}

/** Warmest color with same chroma and tone as input. */
- (MCUHct *)getWarmest {
  NSArray<MCUHct *> *byTemp = [self getHctsByTemp];
  return byTemp[byTemp.count - 1];
}

/** Determines if an angle is between two other angles, rotating clockwise. */
+ (BOOL)isBetween:(double)angle a:(double)a b:(double)b {
  if (a < b) {
    return a <= angle && angle <= b;
  }
  return a <= angle || angle <= b;
}

@end
