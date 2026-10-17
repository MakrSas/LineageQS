// Port of upstream/aosp-libmonet/palettes/TonalPalette.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUTonalPalette.h"
#import "MCUHct.h"
#import "MCUKeyColor.h"
#import "MCUMathUtils.h"

@interface MCUTonalPalette ()
- (instancetype)initWithHue:(double)hue chroma:(double)chroma keyColor:(MCUHct *)keyColor;
- (int)averageArgb:(int)argb1 argb2:(int)argb2;
@end

@implementation MCUTonalPalette {
  NSMutableDictionary<NSNumber *, NSNumber *> *_cache;
  MCUHct *_keyColor;
  double _hue;
  double _chroma;
}

+ (MCUTonalPalette *)fromInt:(int)argb {
  return [MCUTonalPalette fromHct:[MCUHct fromInt:argb]];
}

+ (MCUTonalPalette *)fromHct:(MCUHct *)hct {
  return [[MCUTonalPalette alloc] initWithHue:[hct getHue] chroma:[hct getChroma] keyColor:hct];
}

+ (MCUTonalPalette *)fromHueAndChroma:(double)hue chroma:(double)chroma {
  MCUHct *keyColor = [[[MCUKeyColor alloc] initWithHue:hue requestedChroma:chroma] create];
  return [[MCUTonalPalette alloc] initWithHue:hue chroma:chroma keyColor:keyColor];
}

- (instancetype)initWithHue:(double)hue chroma:(double)chroma keyColor:(MCUHct *)keyColor {
  self = [super init];
  if (self) {
    _cache = [NSMutableDictionary dictionary];
    _hue = hue;
    _chroma = chroma;
    _keyColor = keyColor;
  }
  return self;
}

- (int)tone:(int)tone {
  NSNumber *key = @(tone);
  NSNumber *color = _cache[key];
  if (color == nil) {
    int argb;
    if (tone == 99 && [MCUHct isYellow:_hue]) {
      argb = [self averageArgb:[self tone:98] argb2:[self tone:100]];
    } else {
      argb = [[MCUHct from:_hue chroma:_chroma tone:tone] toInt];
    }
    color = @(argb);
    _cache[key] = color;
  }
  return color.intValue;
}

- (MCUHct *)getHct:(double)tone {
  return [MCUHct from:_hue chroma:_chroma tone:tone];
}

- (double)getChroma {
  return _chroma;
}

- (double)getHue {
  return _hue;
}

- (MCUHct *)getKeyColor {
  return _keyColor;
}

- (int)averageArgb:(int)argb1 argb2:(int)argb2 {
  int red1 = (int)(((unsigned)argb1 >> 16) & 0xff);
  int green1 = (int)(((unsigned)argb1 >> 8) & 0xff);
  int blue1 = argb1 & 0xff;
  int red2 = (int)(((unsigned)argb2 >> 16) & 0xff);
  int green2 = (int)(((unsigned)argb2 >> 8) & 0xff);
  int blue2 = argb2 & 0xff;
  // Java: Math.round((red1 + red2) / 2f) -- float division, Math.round(float) returns int.
  int red = (int)floorf((float)(red1 + red2) / 2.0f + 0.5f);
  int green = (int)floorf((float)(green1 + green2) / 2.0f + 0.5f);
  int blue = (int)floorf((float)(blue1 + blue2) / 2.0f + 0.5f);
  return (int)((((unsigned)255) << 24) | (((unsigned)(red & 255)) << 16) |
               (((unsigned)(green & 255)) << 8) | ((unsigned)(blue & 255)));
}

@end
