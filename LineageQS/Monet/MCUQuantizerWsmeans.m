// Port of upstream/aosp-libmonet/quantize/QuantizerWsmeans.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes:
//  - java.util.Random(0x42688) is reproduced exactly (48-bit LCG, nextInt(bound) incl. the
//    power-of-two branch and the rejection loop). The Random class is private to this file.
//  - Java's Distance[][] matrix: rows are sorted in place (Arrays.sort on the row), and every write
//    goes to the element at a *position* after earlier sorts. Reproduced with a plain struct matrix
//    sorted in place. Arrays.sort on objects is stable; a stable insertion sort gives the same order.
//  - Java `indexMatrix` is written but never read; it is omitted here (no observable effect).
//  - Java `Map` results keep LinkedHashMap insertion order via MCUQuantizerResult.colorOrder.

#import "MCUQuantizerWsmeans.h"
#import "MCUQuantizerResult.h"
#import "MCUPointProviderLab.h"
#import "MCUMathUtils.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static const int kMCUWsMaxIterations = 10;
static const double kMCUWsMinMovementDistance = 3.0;

typedef struct {
  uint64_t seed;
} MCUJavaRandom;

#define MCU_JAVA_RANDOM_MULTIPLIER 0x5DEECE66DULL
#define MCU_JAVA_RANDOM_MASK ((1ULL << 48) - 1)

static void MCUJavaRandomInit(MCUJavaRandom *rnd, int64_t seed) {
  rnd->seed = ((uint64_t)seed ^ MCU_JAVA_RANDOM_MULTIPLIER) & MCU_JAVA_RANDOM_MASK;
}

static int32_t MCUJavaRandomNext(MCUJavaRandom *rnd, int bits) {
  rnd->seed = (rnd->seed * MCU_JAVA_RANDOM_MULTIPLIER + 0xBULL) & MCU_JAVA_RANDOM_MASK;
  return (int32_t)(uint32_t)(rnd->seed >> (48 - bits));
}

static int32_t MCUJavaRandomNextInt(MCUJavaRandom *rnd, int32_t bound) {
  int32_t r = MCUJavaRandomNext(rnd, 31);
  int32_t m = bound - 1;
  if ((bound & m) == 0) {
    // (int)((bound * (long)r) >> 31)
    r = (int32_t)(((int64_t)bound * (int64_t)r) >> 31);
  } else {
    for (int32_t u = r; (int32_t)((uint32_t)u - (uint32_t)(r = u % bound) + (uint32_t)m) < 0;
         u = MCUJavaRandomNext(rnd, 31)) {
    }
  }
  return r;
}

// Mirrors Java's Distance class (index = -1, distance = -1 initially).
typedef struct {
  int index;
  double distance;
} MCUWsDistance;

// Stable insertion sort by Double.compareTo on the distance field (Java Arrays.sort on objects is stable).
static void MCUWsSortRow(MCUWsDistance *row, int n) {
  for (int i = 1; i < n; i++) {
    MCUWsDistance cur = row[i];
    int j = i;
    while (j > 0 && MCUJavaDoubleCompare(row[j - 1].distance, cur.distance) > 0) {
      row[j] = row[j - 1];
      j--;
    }
    row[j] = cur;
  }
}

@implementation MCUQuantizerWsmeans

+ (MCUQuantizerResult *)quantize:(NSArray<NSNumber *> *)inputPixels
                startingClusters:(NSArray<NSNumber *> *)startingClusters
                       maxColors:(int)maxColors {
  // Uses a seeded random number generator to ensure consistent results.
  MCUJavaRandom random;
  MCUJavaRandomInit(&random, 0x42688);

  NSUInteger inputCount = inputPixels.count;
  // LinkedHashMap pixelToCount: insertion order = first occurrence.
  NSMutableDictionary<NSNumber *, NSNumber *> *pixelToCount = [NSMutableDictionary dictionary];
  double *points = calloc(inputCount * 3 + 3, sizeof(double));
  int *pixels = calloc(inputCount + 1, sizeof(int));
  MCUPointProviderLab *pointProvider = [[MCUPointProviderLab alloc] init];

  int pointCount = 0;
  for (NSUInteger i = 0; i < inputCount; i++) {
    int inputPixel = [inputPixels[i] intValue];
    NSNumber *key = @(inputPixel);
    NSNumber *pixelCount = pixelToCount[key];
    if (pixelCount == nil) {
      [pointProvider fromInt:inputPixel out:&points[pointCount * 3]];
      pixels[pointCount] = inputPixel;
      pointCount++;

      pixelToCount[key] = @1;
    } else {
      pixelToCount[key] = @([pixelCount intValue] + 1);
    }
  }

  int *counts = calloc(pointCount + 1, sizeof(int));
  for (int i = 0; i < pointCount; i++) {
    int pixel = pixels[i];
    counts[i] = [pixelToCount[@(pixel)] intValue];
  }

  int clusterCount = MIN(maxColors, pointCount);
  int startingCount = (int)startingClusters.count;
  if (startingCount != 0) {
    clusterCount = MIN(clusterCount, startingCount);
  }

  // Java: clusters = new double[clusterCount][]; the starting clusters fill the first slots.
  // (Java throws ArrayIndexOutOfBoundsException if startingClusters is longer than clusterCount.)
  double *clusters = calloc(clusterCount * 3 + 3, sizeof(double));
  int clustersCreated = 0;
  for (int i = 0; i < startingCount; i++) {
    [pointProvider fromInt:[startingClusters[i] intValue] out:&clusters[i * 3]];
    clustersCreated++;
  }

  int additionalClustersNeeded = clusterCount - clustersCreated;
  if (additionalClustersNeeded > 0) {
    for (int i = 0; i < additionalClustersNeeded; i++) {
      // Java: empty loop body.
    }
  }

  int *clusterIndices = calloc(pointCount + 1, sizeof(int));
  for (int i = 0; i < pointCount; i++) {
    clusterIndices[i] = MCUJavaRandomNextInt(&random, clusterCount);
  }

  MCUWsDistance *distanceToIndexMatrix = calloc(clusterCount * clusterCount + 1, sizeof(MCUWsDistance));
  for (int i = 0; i < clusterCount; i++) {
    for (int j = 0; j < clusterCount; j++) {
      distanceToIndexMatrix[i * clusterCount + j].index = -1;
      distanceToIndexMatrix[i * clusterCount + j].distance = -1;
    }
  }

  int *pixelCountSums = calloc(clusterCount + 1, sizeof(int));
  for (int iteration = 0; iteration < kMCUWsMaxIterations; iteration++) {
    for (int i = 0; i < clusterCount; i++) {
      for (int j = i + 1; j < clusterCount; j++) {
        double distance = [pointProvider distance:&clusters[i * 3] b:&clusters[j * 3]];
        distanceToIndexMatrix[j * clusterCount + i].distance = distance;
        distanceToIndexMatrix[j * clusterCount + i].index = i;
        distanceToIndexMatrix[i * clusterCount + j].distance = distance;
        distanceToIndexMatrix[i * clusterCount + j].index = j;
      }
      MCUWsSortRow(&distanceToIndexMatrix[i * clusterCount], clusterCount);
    }

    int pointsMoved = 0;
    for (int i = 0; i < pointCount; i++) {
      double *point = &points[i * 3];
      int previousClusterIndex = clusterIndices[i];
      double *previousCluster = &clusters[previousClusterIndex * 3];
      double previousDistance = [pointProvider distance:point b:previousCluster];

      double minimumDistance = previousDistance;
      int newClusterIndex = -1;
      for (int j = 0; j < clusterCount; j++) {
        if (distanceToIndexMatrix[previousClusterIndex * clusterCount + j].distance >= 4 * previousDistance) {
          continue;
        }
        double distance = [pointProvider distance:point b:&clusters[j * 3]];
        if (distance < minimumDistance) {
          minimumDistance = distance;
          newClusterIndex = j;
        }
      }
      if (newClusterIndex != -1) {
        double distanceChange = fabs(sqrt(minimumDistance) - sqrt(previousDistance));
        if (distanceChange > kMCUWsMinMovementDistance) {
          pointsMoved++;
          clusterIndices[i] = newClusterIndex;
        }
      }
    }

    if (pointsMoved == 0 && iteration != 0) {
      break;
    }

    double *componentASums = calloc(clusterCount + 1, sizeof(double));
    double *componentBSums = calloc(clusterCount + 1, sizeof(double));
    double *componentCSums = calloc(clusterCount + 1, sizeof(double));
    memset(pixelCountSums, 0, sizeof(int) * (clusterCount + 1));
    for (int i = 0; i < pointCount; i++) {
      int clusterIndex = clusterIndices[i];
      double *point = &points[i * 3];
      int count = counts[i];
      pixelCountSums[clusterIndex] += count;
      componentASums[clusterIndex] += (point[0] * count);
      componentBSums[clusterIndex] += (point[1] * count);
      componentCSums[clusterIndex] += (point[2] * count);
    }

    for (int i = 0; i < clusterCount; i++) {
      int count = pixelCountSums[i];
      if (count == 0) {
        clusters[i * 3 + 0] = 0.;
        clusters[i * 3 + 1] = 0.;
        clusters[i * 3 + 2] = 0.;
        continue;
      }
      double a = componentASums[i] / count;
      double b = componentBSums[i] / count;
      double c = componentCSums[i] / count;
      clusters[i * 3 + 0] = a;
      clusters[i * 3 + 1] = b;
      clusters[i * 3 + 2] = c;
    }

    free(componentASums);
    free(componentBSums);
    free(componentCSums);
  }

  // LinkedHashMap argbToPopulation.
  NSMutableDictionary<NSNumber *, NSNumber *> *argbToPopulation = [NSMutableDictionary dictionary];
  NSMutableArray<NSNumber *> *order = [NSMutableArray array];
  for (int i = 0; i < clusterCount; i++) {
    int count = pixelCountSums[i];
    if (count == 0) {
      continue;
    }

    int possibleNewCluster = [pointProvider toInt:&clusters[i * 3]];
    NSNumber *key = @(possibleNewCluster);
    if (argbToPopulation[key] != nil) {
      continue;
    }

    [order addObject:key];
    argbToPopulation[key] = @(count);
  }

  free(points);
  free(pixels);
  free(counts);
  free(clusters);
  free(clusterIndices);
  free(distanceToIndexMatrix);
  free(pixelCountSums);

  return [[MCUQuantizerResult alloc] initWithColorToCount:argbToPopulation colorOrder:order];
}

@end
