// Port of upstream/aosp-libmonet/quantize/PointProvider.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Port notes: Java `double[]` points are plain C buffers of 3 doubles owned by the caller
// (the quantizers call this in tight loops; NSArray boxing would be prohibitively slow).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MCUPointProvider <NSObject>

/** The three components in the color space of an sRGB color. Writes 3 doubles to `out`. */
- (void)fromInt:(int)argb out:(double *)out;

/** The ARGB representation of the 3-component point `point`. */
- (int)toInt:(const double *)point;

/** Squared distance between two points (delta E, without the square root). */
- (double)distance:(const double *)a b:(const double *)b;

@end

NS_ASSUME_NONNULL_END
