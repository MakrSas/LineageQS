// Port of upstream/aosp-libmonet/quantize/QuantizerWu.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes:
//  - Java int arithmetic wraps modulo 2^32 (moments, hypotenuse, half-sums); it is reproduced with
//    the MCU_I32_* macros, which compute in uint32_t and convert back to int32_t.
//  - Java's Box and nested result objects are plain C structs (MCUQuantizerWuBox, ...).
//  - Java's int[] / double[] fields are malloc'd C arrays owned by the instance.

#import "MCUQuantizerWu.h"
#import "MCUQuantizerMap.h"
#import "MCUQuantizerResult.h"
#import "MCUColorUtils.h"
#include <stdint.h>
#include <stdlib.h>

#define MCU_I32_ADD(a, b) ((int32_t)((uint32_t)(a) + (uint32_t)(b)))
#define MCU_I32_SUB(a, b) ((int32_t)((uint32_t)(a) - (uint32_t)(b)))
#define MCU_I32_MUL(a, b) ((int32_t)((uint32_t)(a) * (uint32_t)(b)))

static const int kMCUWuIndexBits = 5;
static const int kMCUWuIndexCount = 33;   // ((1 << INDEX_BITS) + 1); the local arrays in createMoments are sized 33 to match
static const int kMCUWuTotalSize = 35937; // INDEX_COUNT * INDEX_COUNT * INDEX_COUNT

typedef struct {
  int r0;
  int r1;
  int g0;
  int g1;
  int b0;
  int b1;
  int vol;
} MCUQuantizerWuBox;

typedef NS_ENUM(NSInteger, MCUDirection) {
  MCUDirectionRed,
  MCUDirectionGreen,
  MCUDirectionBlue,
};

typedef struct {
  // < 0 if cut impossible
  int cutLocation;
  double maximum;
} MCUQuantizerWuMaximizeResult;

@interface MCUQuantizerWu () {
  int32_t *_weights;
  int32_t *_momentsR;
  int32_t *_momentsG;
  int32_t *_momentsB;
  double *_moments;
  MCUQuantizerWuBox *_cubes;
}

+ (int)getIndex:(int)r g:(int)g b:(int)b;
+ (int32_t)volume:(MCUQuantizerWuBox *)cube moment:(const int32_t *)moment;
+ (int32_t)bottom:(MCUQuantizerWuBox *)cube direction:(MCUDirection)direction moment:(const int32_t *)moment;
+ (int32_t)top:(MCUQuantizerWuBox *)cube direction:(MCUDirection)direction position:(int)position moment:(const int32_t *)moment;

- (void)constructHistogram:(NSDictionary<NSNumber *, NSNumber *> *)pixels order:(NSArray<NSNumber *> *)order;
- (void)createMoments;
- (int)createBoxes:(int)maxColorCount;
- (NSArray<NSNumber *> *)createResult:(int)colorCount;
- (double)variance:(MCUQuantizerWuBox *)cube;
- (BOOL)cut:(MCUQuantizerWuBox *)one two:(MCUQuantizerWuBox *)two;
- (MCUQuantizerWuMaximizeResult)maximize:(MCUQuantizerWuBox *)cube
                               direction:(MCUDirection)direction
                                   first:(int)first
                                    last:(int)last
                                  wholeR:(int32_t)wholeR
                                  wholeG:(int32_t)wholeG
                                  wholeB:(int32_t)wholeB
                                  wholeW:(int32_t)wholeW;

@end

@implementation MCUQuantizerWu

- (void)dealloc {
  free(_weights);
  free(_momentsR);
  free(_momentsG);
  free(_momentsB);
  free(_moments);
  free(_cubes);
}

- (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)pixels maxColors:(int)colorCount {
  MCUQuantizerResult *mapResult = [[[MCUQuantizerMap alloc] init] quantize:pixels maxColors:colorCount];
  [self constructHistogram:mapResult.colorToCount order:mapResult.colorOrder];
  [self createMoments];
  int resultCount = [self createBoxes:colorCount];
  NSArray<NSNumber *> *colors = [self createResult:resultCount];
  NSMutableDictionary<NSNumber *, NSNumber *> *resultMap = [NSMutableDictionary dictionary];
  NSMutableArray<NSNumber *> *order = [NSMutableArray array];
  for (NSNumber *color in colors) {
    if (resultMap[color] == nil) {
      [order addObject:color];
    }
    resultMap[color] = @0;
  }
  return [[MCUQuantizerResult alloc] initWithColorToCount:resultMap colorOrder:order];
}

+ (int)getIndex:(int)r g:(int)g b:(int)b {
  return (r << (kMCUWuIndexBits * 2)) + (r << (kMCUWuIndexBits + 1)) + r + (g << kMCUWuIndexBits) + g + b;
}

- (void)constructHistogram:(NSDictionary<NSNumber *, NSNumber *> *)pixels order:(NSArray<NSNumber *> *)order {
  _weights = calloc(kMCUWuTotalSize, sizeof(int32_t));
  _momentsR = calloc(kMCUWuTotalSize, sizeof(int32_t));
  _momentsG = calloc(kMCUWuTotalSize, sizeof(int32_t));
  _momentsB = calloc(kMCUWuTotalSize, sizeof(int32_t));
  _moments = calloc(kMCUWuTotalSize, sizeof(double));

  for (NSNumber *pixelKey in order) {
    int pixel = [pixelKey intValue];
    int count = [pixels[pixelKey] intValue];
    int red = [MCUColorUtils redFromArgb:pixel];
    int green = [MCUColorUtils greenFromArgb:pixel];
    int blue = [MCUColorUtils blueFromArgb:pixel];
    int bitsToRemove = 8 - kMCUWuIndexBits;
    int iR = (red >> bitsToRemove) + 1;
    int iG = (green >> bitsToRemove) + 1;
    int iB = (blue >> bitsToRemove) + 1;
    int index = [MCUQuantizerWu getIndex:iR g:iG b:iB];
    _weights[index] = MCU_I32_ADD(_weights[index], count);
    _momentsR[index] = MCU_I32_ADD(_momentsR[index], MCU_I32_MUL(red, count));
    _momentsG[index] = MCU_I32_ADD(_momentsG[index], MCU_I32_MUL(green, count));
    _momentsB[index] = MCU_I32_ADD(_momentsB[index], MCU_I32_MUL(blue, count));
    int32_t sumOfSquares = MCU_I32_ADD(MCU_I32_ADD(MCU_I32_MUL(red, red), MCU_I32_MUL(green, green)),
                                       MCU_I32_MUL(blue, blue));
    // Java: moments[index] += (count * (...)) -- the int product wraps before widening to double.
    _moments[index] += (double)MCU_I32_MUL(count, sumOfSquares);
  }
}

- (void)createMoments {
  for (int r = 1; r < kMCUWuIndexCount; ++r) {
    int32_t area[33];
    int32_t areaR[33];
    int32_t areaG[33];
    int32_t areaB[33];
    double area2[33];
    for (int k = 0; k < 33; k++) {
      area[k] = 0;
      areaR[k] = 0;
      areaG[k] = 0;
      areaB[k] = 0;
      area2[k] = 0.0;
    }

    for (int g = 1; g < kMCUWuIndexCount; ++g) {
      int32_t line = 0;
      int32_t lineR = 0;
      int32_t lineG = 0;
      int32_t lineB = 0;
      double line2 = 0.0;
      for (int b = 1; b < kMCUWuIndexCount; ++b) {
        int index = [MCUQuantizerWu getIndex:r g:g b:b];
        line = MCU_I32_ADD(line, _weights[index]);
        lineR = MCU_I32_ADD(lineR, _momentsR[index]);
        lineG = MCU_I32_ADD(lineG, _momentsG[index]);
        lineB = MCU_I32_ADD(lineB, _momentsB[index]);
        line2 += _moments[index];

        area[b] = MCU_I32_ADD(area[b], line);
        areaR[b] = MCU_I32_ADD(areaR[b], lineR);
        areaG[b] = MCU_I32_ADD(areaG[b], lineG);
        areaB[b] = MCU_I32_ADD(areaB[b], lineB);
        area2[b] += line2;

        int previousIndex = [MCUQuantizerWu getIndex:r - 1 g:g b:b];
        _weights[index] = MCU_I32_ADD(_weights[previousIndex], area[b]);
        _momentsR[index] = MCU_I32_ADD(_momentsR[previousIndex], areaR[b]);
        _momentsG[index] = MCU_I32_ADD(_momentsG[previousIndex], areaG[b]);
        _momentsB[index] = MCU_I32_ADD(_momentsB[previousIndex], areaB[b]);
        _moments[index] = _moments[previousIndex] + area2[b];
      }
    }
  }
}

// Returns Java's generatedColorCount (createBoxes' resultCount).
- (int)createBoxes:(int)maxColorCount {
  _cubes = calloc(maxColorCount, sizeof(MCUQuantizerWuBox));
  double *volumeVariance = calloc(maxColorCount, sizeof(double));
  MCUQuantizerWuBox *firstBox = &_cubes[0];
  firstBox->r1 = kMCUWuIndexCount - 1;
  firstBox->g1 = kMCUWuIndexCount - 1;
  firstBox->b1 = kMCUWuIndexCount - 1;

  int generatedColorCount = maxColorCount;
  int next = 0;
  for (int i = 1; i < maxColorCount; i++) {
    if ([self cut:&_cubes[next] two:&_cubes[i]]) {
      volumeVariance[next] = (_cubes[next].vol > 1) ? [self variance:&_cubes[next]] : 0.0;
      volumeVariance[i] = (_cubes[i].vol > 1) ? [self variance:&_cubes[i]] : 0.0;
    } else {
      volumeVariance[next] = 0.0;
      i--;
    }

    next = 0;

    double temp = volumeVariance[0];
    for (int j = 1; j <= i; j++) {
      if (volumeVariance[j] > temp) {
        temp = volumeVariance[j];
        next = j;
      }
    }
    if (temp <= 0.0) {
      generatedColorCount = i + 1;
      break;
    }
  }

  free(volumeVariance);
  return generatedColorCount;
}

- (NSArray<NSNumber *> *)createResult:(int)colorCount {
  NSMutableArray<NSNumber *> *colors = [NSMutableArray array];
  for (int i = 0; i < colorCount; ++i) {
    MCUQuantizerWuBox *cube = &_cubes[i];
    int32_t weight = [MCUQuantizerWu volume:cube moment:_weights];
    if (weight > 0) {
      int32_t r = [MCUQuantizerWu volume:cube moment:_momentsR] / weight;
      int32_t g = [MCUQuantizerWu volume:cube moment:_momentsG] / weight;
      int32_t b = [MCUQuantizerWu volume:cube moment:_momentsB] / weight;
      uint32_t argb = 0xFF000000u | ((uint32_t)(r & 0x0ff) << 16) | ((uint32_t)(g & 0x0ff) << 8) |
                      (uint32_t)(b & 0x0ff);
      [colors addObject:@((int)(int32_t)argb)];
    }
  }
  return colors;
}

- (double)variance:(MCUQuantizerWuBox *)cube {
  int32_t dr = [MCUQuantizerWu volume:cube moment:_momentsR];
  int32_t dg = [MCUQuantizerWu volume:cube moment:_momentsG];
  int32_t db = [MCUQuantizerWu volume:cube moment:_momentsB];
  double xx = _moments[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:cube->b1]]
              - _moments[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:cube->b0]]
              - _moments[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b1]]
              + _moments[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b0]]
              - _moments[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b1]]
              + _moments[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b0]]
              + _moments[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b1]]
              - _moments[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b0]];

  int32_t hypotenuse = MCU_I32_ADD(MCU_I32_ADD(MCU_I32_MUL(dr, dr), MCU_I32_MUL(dg, dg)),
                                   MCU_I32_MUL(db, db));
  int32_t volume = [MCUQuantizerWu volume:cube moment:_weights];
  return xx - hypotenuse / ((double)volume);
}

- (BOOL)cut:(MCUQuantizerWuBox *)one two:(MCUQuantizerWuBox *)two {
  int32_t wholeR = [MCUQuantizerWu volume:one moment:_momentsR];
  int32_t wholeG = [MCUQuantizerWu volume:one moment:_momentsG];
  int32_t wholeB = [MCUQuantizerWu volume:one moment:_momentsB];
  int32_t wholeW = [MCUQuantizerWu volume:one moment:_weights];

  MCUQuantizerWuMaximizeResult maxRResult =
      [self maximize:one direction:MCUDirectionRed first:one->r0 + 1 last:one->r1
              wholeR:wholeR wholeG:wholeG wholeB:wholeB wholeW:wholeW];
  MCUQuantizerWuMaximizeResult maxGResult =
      [self maximize:one direction:MCUDirectionGreen first:one->g0 + 1 last:one->g1
              wholeR:wholeR wholeG:wholeG wholeB:wholeB wholeW:wholeW];
  MCUQuantizerWuMaximizeResult maxBResult =
      [self maximize:one direction:MCUDirectionBlue first:one->b0 + 1 last:one->b1
              wholeR:wholeR wholeG:wholeG wholeB:wholeB wholeW:wholeW];
  MCUDirection cutDirection;
  double maxR = maxRResult.maximum;
  double maxG = maxGResult.maximum;
  double maxB = maxBResult.maximum;
  if (maxR >= maxG && maxR >= maxB) {
    if (maxRResult.cutLocation < 0) {
      return NO;
    }
    cutDirection = MCUDirectionRed;
  } else if (maxG >= maxR && maxG >= maxB) {
    cutDirection = MCUDirectionGreen;
  } else {
    cutDirection = MCUDirectionBlue;
  }

  two->r1 = one->r1;
  two->g1 = one->g1;
  two->b1 = one->b1;

  switch (cutDirection) {
    case MCUDirectionRed:
      one->r1 = maxRResult.cutLocation;
      two->r0 = one->r1;
      two->g0 = one->g0;
      two->b0 = one->b0;
      break;
    case MCUDirectionGreen:
      one->g1 = maxGResult.cutLocation;
      two->r0 = one->r0;
      two->g0 = one->g1;
      two->b0 = one->b0;
      break;
    case MCUDirectionBlue:
      one->b1 = maxBResult.cutLocation;
      two->r0 = one->r0;
      two->g0 = one->g0;
      two->b0 = one->b1;
      break;
  }

  one->vol = (one->r1 - one->r0) * (one->g1 - one->g0) * (one->b1 - one->b0);
  two->vol = (two->r1 - two->r0) * (two->g1 - two->g0) * (two->b1 - two->b0);

  return YES;
}

- (MCUQuantizerWuMaximizeResult)maximize:(MCUQuantizerWuBox *)cube
                               direction:(MCUDirection)direction
                                   first:(int)first
                                    last:(int)last
                                  wholeR:(int32_t)wholeR
                                  wholeG:(int32_t)wholeG
                                  wholeB:(int32_t)wholeB
                                  wholeW:(int32_t)wholeW {
  int32_t bottomR = [MCUQuantizerWu bottom:cube direction:direction moment:_momentsR];
  int32_t bottomG = [MCUQuantizerWu bottom:cube direction:direction moment:_momentsG];
  int32_t bottomB = [MCUQuantizerWu bottom:cube direction:direction moment:_momentsB];
  int32_t bottomW = [MCUQuantizerWu bottom:cube direction:direction moment:_weights];

  double max = 0.0;
  int cut = -1;

  int32_t halfR = 0;
  int32_t halfG = 0;
  int32_t halfB = 0;
  int32_t halfW = 0;
  for (int i = first; i < last; i++) {
    halfR = MCU_I32_ADD(bottomR, [MCUQuantizerWu top:cube direction:direction position:i moment:_momentsR]);
    halfG = MCU_I32_ADD(bottomG, [MCUQuantizerWu top:cube direction:direction position:i moment:_momentsG]);
    halfB = MCU_I32_ADD(bottomB, [MCUQuantizerWu top:cube direction:direction position:i moment:_momentsB]);
    halfW = MCU_I32_ADD(bottomW, [MCUQuantizerWu top:cube direction:direction position:i moment:_weights]);
    if (halfW == 0) {
      continue;
    }

    double tempNumerator = (double)MCU_I32_ADD(
        MCU_I32_ADD(MCU_I32_MUL(halfR, halfR), MCU_I32_MUL(halfG, halfG)), MCU_I32_MUL(halfB, halfB));
    double tempDenominator = (double)halfW;
    double temp = tempNumerator / tempDenominator;

    halfR = MCU_I32_SUB(wholeR, halfR);
    halfG = MCU_I32_SUB(wholeG, halfG);
    halfB = MCU_I32_SUB(wholeB, halfB);
    halfW = MCU_I32_SUB(wholeW, halfW);
    if (halfW == 0) {
      continue;
    }

    tempNumerator = (double)MCU_I32_ADD(
        MCU_I32_ADD(MCU_I32_MUL(halfR, halfR), MCU_I32_MUL(halfG, halfG)), MCU_I32_MUL(halfB, halfB));
    tempDenominator = (double)halfW;
    temp += (tempNumerator / tempDenominator);

    if (temp > max) {
      max = temp;
      cut = i;
    }
  }
  MCUQuantizerWuMaximizeResult result = {cut, max};
  return result;
}

+ (int32_t)volume:(MCUQuantizerWuBox *)cube moment:(const int32_t *)moment {
  uint32_t v = (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:cube->b1]]
               - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:cube->b0]]
               - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b1]]
               + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b0]]
               - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b1]]
               + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b0]]
               + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b1]]
               - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b0]];
  return (int32_t)v;
}

+ (int32_t)bottom:(MCUQuantizerWuBox *)cube direction:(MCUDirection)direction moment:(const int32_t *)moment {
  uint32_t v;
  switch (direction) {
    case MCUDirectionRed:
      v = 0u - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b1]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b0]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b1]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b0]];
      break;
    case MCUDirectionGreen:
      v = 0u - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b1]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b0]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b1]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b0]];
      break;
    case MCUDirectionBlue:
    default:
      v = 0u - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:cube->b0]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:cube->b0]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:cube->b0]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:cube->b0]];
      break;
  }
  return (int32_t)v;
}

+ (int32_t)top:(MCUQuantizerWuBox *)cube direction:(MCUDirection)direction position:(int)position moment:(const int32_t *)moment {
  uint32_t v;
  switch (direction) {
    case MCUDirectionRed:
      v = (uint32_t)moment[[MCUQuantizerWu getIndex:position g:cube->g1 b:cube->b1]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:position g:cube->g1 b:cube->b0]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:position g:cube->g0 b:cube->b1]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:position g:cube->g0 b:cube->b0]];
      break;
    case MCUDirectionGreen:
      v = (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:position b:cube->b1]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:position b:cube->b0]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:position b:cube->b1]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:position b:cube->b0]];
      break;
    case MCUDirectionBlue:
    default:
      v = (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g1 b:position]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r1 g:cube->g0 b:position]]
          - (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g1 b:position]]
          + (uint32_t)moment[[MCUQuantizerWu getIndex:cube->r0 g:cube->g0 b:position]];
      break;
  }
  return (int32_t)v;
}

@end
