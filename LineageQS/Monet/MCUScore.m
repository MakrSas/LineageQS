// Port of upstream/aosp-libmonet/score/Score.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes:
//  - Collections.sort is stable; a stable insertion sort (same comparator, Double.compare semantics)
//    yields the same order. The sorted list is at most the number of distinct input colors.
//  - Java `Math.round` is MCUJavaRound; Java `(int)` casts are explicit.

#import "MCUScore.h"
#import "MCUHct.h"
#import "MCUMathUtils.h"

static const double kMCUScoreTargetChroma = 48.; // A1 Chroma
static const double kMCUScoreWeightProportion = 0.7;
static const double kMCUScoreWeightChromaAbove = 0.3;
static const double kMCUScoreWeightChromaBelow = 0.1;
static const double kMCUScoreCutoffChroma = 5.;
static const double kMCUScoreCutoffExcitedProportion = 0.01;

// Mirrors Java's ScoredHCT; `hctIndex` refers to colorsHct.
typedef struct {
  int hctIndex;
  double score;
} MCUScoredHct;

@implementation MCUScore

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation {
  return [self score:colorsToPopulation keyOrder:colorsToPopulation.allKeys desired:4 fallbackColorArgb:(int)0xff4285f4 filter:YES];
}

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation desired:(int)desired {
  return [self score:colorsToPopulation keyOrder:colorsToPopulation.allKeys desired:desired fallbackColorArgb:(int)0xff4285f4 filter:YES];
}

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb {
  return [self score:colorsToPopulation keyOrder:colorsToPopulation.allKeys desired:desired fallbackColorArgb:fallbackColorArgb filter:YES];
}

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb
                        filter:(BOOL)filter {
  return [self score:colorsToPopulation keyOrder:colorsToPopulation.allKeys desired:desired fallbackColorArgb:fallbackColorArgb filter:filter];
}

+ (NSArray<NSNumber *> *)score:(NSDictionary<NSNumber *, NSNumber *> *)colorsToPopulation
                      keyOrder:(NSArray<NSNumber *> *)keyOrder
                       desired:(int)desired
             fallbackColorArgb:(int)fallbackColorArgb
                        filter:(BOOL)filter {
  // Get the HCT color for each Argb value, while finding the per hue count and
  // total count.
  NSMutableArray<MCUHct *> *colorsHct = [NSMutableArray array];
  int huePopulation[360] = {0};
  double populationSum = 0.;
  for (NSNumber *key in keyOrder) {
    int entryKey = [key intValue];
    int entryValue = [colorsToPopulation[@(entryKey)] intValue];
    MCUHct *hct = [MCUHct fromInt:entryKey];
    [colorsHct addObject:hct];
    int hue = (int)floor([hct getHue]);
    huePopulation[hue] += entryValue;
    populationSum += entryValue;
  }

  // Hues with more usage in neighboring 30 degree slice get a larger number.
  double hueExcitedProportions[360] = {0};
  for (int hue = 0; hue < 360; hue++) {
    double proportion = huePopulation[hue] / populationSum;
    for (int i = hue - 14; i < hue + 16; i++) {
      int neighborHue = [MCUMathUtils sanitizeDegreesInt:i];
      hueExcitedProportions[neighborHue] += proportion;
    }
  }

  // Scores each HCT color based on usage and chroma, while optionally
  // filtering out values that do not have enough chroma or usage.
  NSUInteger hctCount = colorsHct.count;
  MCUScoredHct *scoredHcts = calloc(hctCount + 1, sizeof(MCUScoredHct));
  int scoredCount = 0;
  for (NSUInteger k = 0; k < hctCount; k++) {
    MCUHct *hct = colorsHct[k];
    int hue = [MCUMathUtils sanitizeDegreesInt:(int)MCUJavaRound([hct getHue])];
    double proportion = hueExcitedProportions[hue];
    if (filter && ([hct getChroma] < kMCUScoreCutoffChroma || proportion <= kMCUScoreCutoffExcitedProportion)) {
      continue;
    }

    double proportionScore = proportion * 100.0 * kMCUScoreWeightProportion;
    double chromaWeight = [hct getChroma] < kMCUScoreTargetChroma ? kMCUScoreWeightChromaBelow : kMCUScoreWeightChromaAbove;
    double chromaScore = ([hct getChroma] - kMCUScoreTargetChroma) * chromaWeight;
    double score = proportionScore + chromaScore;
    scoredHcts[scoredCount].hctIndex = (int)k;
    scoredHcts[scoredCount].score = score;
    scoredCount++;
  }

  // Sorted so that colors with higher scores come first (ScoredComparator: Double.compare(b.score, a.score)).
  // Stable insertion sort; equal scores keep their original order, as Collections.sort does.
  for (int i = 1; i < scoredCount; i++) {
    MCUScoredHct cur = scoredHcts[i];
    int j = i;
    while (j > 0 && MCUJavaDoubleCompare(scoredHcts[j - 1].score, cur.score) < 0) {
      // compare(prev, cur) = Double.compare(cur.score, prev.score) > 0  <=>  cur.score > prev.score
      scoredHcts[j] = scoredHcts[j - 1];
      j--;
    }
    scoredHcts[j] = cur;
  }

  // Iterates through potential hue differences in degrees in order to select
  // the colors with the largest distribution of hues possible. Starting at
  // 90 degrees(maximum difference for 4 colors) then decreasing down to a
  // 15 degree minimum.
  NSMutableArray<MCUHct *> *chosenColors = [NSMutableArray array];
  for (int differenceDegrees = 90; differenceDegrees >= 15; differenceDegrees--) {
    [chosenColors removeAllObjects];
    for (int e = 0; e < scoredCount; e++) {
      MCUHct *hct = colorsHct[scoredHcts[e].hctIndex];
      BOOL hasDuplicateHue = NO;
      for (MCUHct *chosenHct in chosenColors) {
        if ([MCUMathUtils differenceDegrees:[hct getHue] b:[chosenHct getHue]] < differenceDegrees) {
          hasDuplicateHue = YES;
          break;
        }
      }
      if (!hasDuplicateHue) {
        [chosenColors addObject:hct];
      }
      if ((int)chosenColors.count >= desired) {
        break;
      }
    }
    if ((int)chosenColors.count >= desired) {
      break;
    }
  }

  NSMutableArray<NSNumber *> *colors = [NSMutableArray array];
  if (chosenColors.count == 0) {
    [colors addObject:@(fallbackColorArgb)];
  }
  for (MCUHct *chosenHct in chosenColors) {
    [colors addObject:@([chosenHct toInt])];
  }

  free(scoredHcts);
  return colors;
}

@end
