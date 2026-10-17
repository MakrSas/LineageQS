// Port of upstream/aosp-libmonet/palettes/CorePalettes.java (libmonet, Apache License 2.0, Copyright Google LLC).
//
// Constructor CorePalettes(primary, secondary, tertiary, neutral, neutralVariant) ->
// initWithPrimary:secondary:tertiary:neutral:neutralVariant:

#import <Foundation/Foundation.h>

@class MCUTonalPalette;

NS_ASSUME_NONNULL_BEGIN

@interface MCUCorePalettes : NSObject

@property (nonatomic, readwrite, strong) MCUTonalPalette *primary;
@property (nonatomic, readwrite, strong) MCUTonalPalette *secondary;
@property (nonatomic, readwrite, strong) MCUTonalPalette *tertiary;
@property (nonatomic, readwrite, strong) MCUTonalPalette *neutral;
@property (nonatomic, readwrite, strong) MCUTonalPalette *neutralVariant;

/** Creates a new CorePalettes. */
- (instancetype)initWithPrimary:(MCUTonalPalette *)primary
                      secondary:(MCUTonalPalette *)secondary
                       tertiary:(MCUTonalPalette *)tertiary
                        neutral:(MCUTonalPalette *)neutral
                  neutralVariant:(MCUTonalPalette *)neutralVariant;

@end

NS_ASSUME_NONNULL_END
