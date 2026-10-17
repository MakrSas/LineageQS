// Port of upstream/aosp-libmonet/palettes/CorePalette.java (libmonet, Apache License 2.0, Copyright Google LLC).
// Deprecated in Java (use DynamicScheme / CorePalettes); ported as-is.
//
// Overloads: none. Java private constructor CorePalette(int argb, boolean isContent) -> initWithArgb:isContent: (in .m).

#import <Foundation/Foundation.h>

@class MCUTonalPalette;

NS_ASSUME_NONNULL_BEGIN

@interface MCUCorePalette : NSObject

@property (nonatomic, readwrite, strong) MCUTonalPalette *a1;
@property (nonatomic, readwrite, strong) MCUTonalPalette *a2;
@property (nonatomic, readwrite, strong) MCUTonalPalette *a3;
@property (nonatomic, readwrite, strong) MCUTonalPalette *n1;
@property (nonatomic, readwrite, strong) MCUTonalPalette *n2;
@property (nonatomic, readwrite, strong) MCUTonalPalette *error;

/** Create key tones from a color. */
+ (MCUCorePalette *)of:(int)argb;

/** Create content key tones from a color. */
+ (MCUCorePalette *)contentOf:(int)argb;

@end

NS_ASSUME_NONNULL_END
