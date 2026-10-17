// Port of upstream/aosp-libmonet/dislike/DislikeAnalyzer.java (libmonet, Apache License 2.0, Copyright Google LLC).
// Java private constructor (throws UnsupportedOperationException) is omitted: utility class, no instances.

#import <Foundation/Foundation.h>

@class MCUHct;

NS_ASSUME_NONNULL_BEGIN

@interface MCUDislikeAnalyzer : NSObject

/** Returns YES if color is disliked (a dark yellow-green that is not neutral). */
+ (BOOL)isDisliked:(MCUHct *)hct;

/** If color is disliked, lighten it to make it likable. */
+ (MCUHct *)fixIfDisliked:(MCUHct *)hct;

@end

NS_ASSUME_NONNULL_END
