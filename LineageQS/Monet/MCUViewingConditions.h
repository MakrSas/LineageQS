// Port of upstream/aosp-libmonet/hct/ViewingConditions.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Overloads: none in Java. Java private constructor -> private initWithN:aw:nbb:ncb:c:nc:rgbD:fl:flRoot:z:
// (declared in the .m). Java getters are package-private for ncb, c, nc, fl, z: exposed here as well.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUViewingConditions : NSObject

/** sRGB-like viewing conditions (background L* 50). Java static field DEFAULT. */
+ (MCUViewingConditions *)DEFAULT;

/**
 * Create ViewingConditions from a simple, physically relevant, set of parameters.
 * whitePoint is an XYZ triple (NSArray of 3 NSNumber).
 */
+ (MCUViewingConditions *)make:(NSArray<NSNumber *> *)whitePoint
             adaptingLuminance:(double)adaptingLuminance
               backgroundLstar:(double)backgroundLstar
                      surround:(double)surround
         discountingIlluminant:(BOOL)discountingIlluminant;

/** sRGB-like viewing conditions with a custom background L*. */
+ (MCUViewingConditions *)defaultWithBackgroundLstar:(double)lstar;

- (double)getAw;
- (double)getN;
- (double)getNbb;
- (double)getNcb;
- (double)getC;
- (double)getNc;
- (NSArray<NSNumber *> *)getRgbD;
- (double)getFl;
- (double)getFlRoot;
- (double)getZ;

@end

NS_ASSUME_NONNULL_END
