// Port of the KeyColor inner class of upstream/aosp-libmonet/palettes/TonalPalette.java
// (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUKeyColor.h"
#import "MCUHct.h"
#import <stdlib.h>

@interface MCUKeyColor ()
- (double)maxChroma:(int)tone;
@end

@implementation MCUKeyColor {
  double _hue;
  double _requestedChroma;
  // Cache that maps tone to max chroma to avoid duplicated HCT calculation.
  NSMutableDictionary<NSNumber *, NSNumber *> *_chromaCache;
}

// private static final double MAX_CHROMA_VALUE = 200.0;
static const double kMCUKeyColorMaxChromaValue = 200.0;

- (instancetype)initWithHue:(double)hue requestedChroma:(double)requestedChroma {
  self = [super init];
  if (self) {
    _hue = hue;
    _requestedChroma = requestedChroma;
    _chromaCache = [NSMutableDictionary dictionary];
  }
  return self;
}

- (MCUHct *)create {
  // Pivot around T50 because T50 has the most chroma available, on
  // average. Thus it is most likely to have a direct answer.
  const int pivotTone = 50;
  const int toneStepSize = 1;
  // Epsilon to accept values slightly higher than the requested chroma.
  const double epsilon = 0.01;

  // Binary search to find the tone that can provide a chroma that is closest
  // to the requested chroma.
  int lowerTone = 0;
  int upperTone = 100;
  while (lowerTone < upperTone) {
    int midTone = (lowerTone + upperTone) / 2;
    BOOL isAscending = [self maxChroma:midTone] < [self maxChroma:midTone + toneStepSize];
    BOOL sufficientChroma = [self maxChroma:midTone] >= _requestedChroma - epsilon;

    if (sufficientChroma) {
      // Either range [lowerTone, midTone] or [midTone, upperTone] has
      // the answer, so search in the range that is closer the pivot tone.
      if (abs(lowerTone - pivotTone) < abs(upperTone - pivotTone)) {
        upperTone = midTone;
      } else {
        if (lowerTone == midTone) {
          return [MCUHct from:_hue chroma:_requestedChroma tone:lowerTone];
        }
        lowerTone = midTone;
      }
    } else {
      // As there is no sufficient chroma in the midTone, follow the direction to the chroma
      // peak.
      if (isAscending) {
        lowerTone = midTone + toneStepSize;
      } else {
        // Keep midTone for potential chroma peak.
        upperTone = midTone;
      }
    }
  }

  return [MCUHct from:_hue chroma:_requestedChroma tone:lowerTone];
}

// Find the maximum chroma for a given tone.
- (double)maxChroma:(int)tone {
  NSNumber *key = @(tone);
  if (_chromaCache[key] == nil) {
    double newChroma = [[MCUHct from:_hue chroma:kMCUKeyColorMaxChromaValue tone:tone] getChroma];
    _chromaCache[key] = @(newChroma);
  }
  return [_chromaCache[key] doubleValue];
}

@end
