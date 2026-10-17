// Port of upstream/aosp-libmonet/hct/Cam16.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Overloads: none in Java with the same name. Java private constructor is declared in the .m as
// initWithHue:chroma:j:q:m:s:jstar:astar:bstar:. Java private static fromJchInViewingConditions is in the .m.
// Java double[] returnArray of xyzInViewingConditions: NSMutableArray<NSNumber *> (filled when non-nil).

#import <Foundation/Foundation.h>
#import "MCUViewingConditions.h"

NS_ASSUME_NONNULL_BEGIN

// Transforms XYZ color space coordinates to 'cone'/'RGB' responses in CAM16 (Java Cam16.XYZ_TO_CAM16RGB).
extern const double MCUCam16XyzToCam16Rgb[3][3];

@interface MCUCam16 : NSObject

/** Distance in CAM16-UCS (delta E style). */
- (double)distance:(MCUCam16 *)other;

/** Hue in CAM16. */
- (double)getHue;
/** Chroma in CAM16. */
- (double)getChroma;
/** Lightness in CAM16. */
- (double)getJ;
/** Brightness in CAM16. */
- (double)getQ;
/** Colorfulness in CAM16. */
- (double)getM;
/** Saturation in CAM16. */
- (double)getS;
/** Lightness coordinate in CAM16-UCS. */
- (double)getJstar;
/** a* coordinate in CAM16-UCS. */
- (double)getAstar;
/** b* coordinate in CAM16-UCS. */
- (double)getBstar;

/** Create a CAM16 color from a color, assuming default viewing conditions. */
+ (MCUCam16 *)fromInt:(int)argb;

/** Create a CAM16 color from a color in defined viewing conditions. */
+ (MCUCam16 *)fromIntInViewingConditions:(int)argb viewingConditions:(MCUViewingConditions *)viewingConditions;

+ (MCUCam16 *)fromXyzInViewingConditions:(double)x
                                       y:(double)y
                                       z:(double)z
                       viewingConditions:(MCUViewingConditions *)viewingConditions;

/** Create a CAM16 color from J, C, h (default viewing conditions). */
+ (MCUCam16 *)fromJch:(double)j c:(double)c h:(double)h;

/** Create a CAM16 color from CAM16-UCS coordinates (default viewing conditions). */
+ (MCUCam16 *)fromUcs:(double)jstar astar:(double)astar bstar:(double)bstar;

+ (MCUCam16 *)fromUcsInViewingConditions:(double)jstar
                                   astar:(double)astar
                                   bstar:(double)bstar
                       viewingConditions:(MCUViewingConditions *)viewingConditions;

/** ARGB representation of the color, default viewing conditions. */
- (int)toInt;

/** ARGB representation of the color, in defined viewing conditions. */
- (int)viewed:(MCUViewingConditions *)viewingConditions;

/**
 * XYZ of the color in the given viewing conditions, [x, y, z]. If returnArray is non-nil it is
 * filled with x, y, z and returned.
 */
- (NSArray<NSNumber *> *)xyzInViewingConditions:(MCUViewingConditions *)viewingConditions
                                    returnArray:(nullable NSMutableArray<NSNumber *> *)returnArray;

@end

NS_ASSUME_NONNULL_END
