// Port of upstream/aosp-libmonet/dislike/DislikeAnalyzer.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUDislikeAnalyzer.h"
#import "MCUHct.h"
#import "MCUMathUtils.h"

@implementation MCUDislikeAnalyzer

+ (BOOL)isDisliked:(MCUHct *)hct {
  // Java: Math.round(...) returns long, compared against double.
  double roundedHue = (double)MCUJavaRound([hct getHue]);
  double roundedChroma = (double)MCUJavaRound([hct getChroma]);
  double roundedTone = (double)MCUJavaRound([hct getTone]);
  BOOL huePasses = roundedHue >= 90.0 && roundedHue <= 111.0;
  BOOL chromaPasses = roundedChroma > 16.0;
  BOOL tonePasses = roundedTone < 65.0;

  return huePasses && chromaPasses && tonePasses;
}

+ (MCUHct *)fixIfDisliked:(MCUHct *)hct {
  if ([MCUDislikeAnalyzer isDisliked:hct]) {
    return [MCUHct from:[hct getHue] chroma:[hct getChroma] tone:70.0];
  }
  return hct;
}

@end
