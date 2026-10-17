// Port of upstream/aosp-libmonet/hct/Hct.java (libmonet, Apache License 2.0, Copyright Google LLC).
#pragma clang fp contract(off)

#import "MCUHct.h"
#import "MCUCam16.h"
#import "MCUColorUtils.h"
#import "MCUHctSolver.h"
#import "MCUMathUtils.h"
#import "MCUViewingConditions.h"

@interface MCUHct ()
- (instancetype)initWithArgb:(int)argb;
- (void)setInternalState:(int)argb;
@end

@implementation MCUHct {
  double _hue;
  double _chroma;
  double _tone;
  int _argb;
}

+ (MCUHct *)from:(double)hue chroma:(double)chroma tone:(double)tone {
  int argb = [MCUHctSolver solveToInt:hue chroma:chroma lstar:tone];
  return [[MCUHct alloc] initWithArgb:argb];
}

+ (MCUHct *)fromInt:(int)argb {
  return [[MCUHct alloc] initWithArgb:argb];
}

- (instancetype)initWithArgb:(int)argb {
  self = [super init];
  if (self) {
    [self setInternalState:argb];
  }
  return self;
}

- (double)getHue {
  return _hue;
}

- (double)getChroma {
  return _chroma;
}

- (double)getTone {
  return _tone;
}

- (int)toInt {
  return _argb;
}

- (void)setHue:(double)newHue {
  [self setInternalState:[MCUHctSolver solveToInt:newHue chroma:_chroma lstar:_tone]];
}

- (void)setChroma:(double)newChroma {
  [self setInternalState:[MCUHctSolver solveToInt:_hue chroma:newChroma lstar:_tone]];
}

- (void)setTone:(double)newTone {
  [self setInternalState:[MCUHctSolver solveToInt:_hue chroma:_chroma lstar:newTone]];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"HCT(%ld, %ld, %ld)",
                                    (long)(int)MCUJavaRound(_hue),
                                    (long)(int)MCUJavaRound(_chroma),
                                    (long)(int)MCUJavaRound(_tone)];
}

+ (BOOL)isBlue:(double)hue {
  return hue >= 250 && hue < 270;
}

+ (BOOL)isYellow:(double)hue {
  return hue >= 105 && hue < 125;
}

+ (BOOL)isCyan:(double)hue {
  return hue >= 170 && hue < 207;
}

- (MCUHct *)inViewingConditions:(MCUViewingConditions *)vc {
  // 1. Use CAM16 to find XYZ coordinates of color in specified VC.
  MCUCam16 *cam16 = [MCUCam16 fromInt:[self toInt]];
  NSArray<NSNumber *> *viewedInVc = [cam16 xyzInViewingConditions:vc returnArray:nil];

  // 2. Create CAM16 of those XYZ coordinates in default VC.
  MCUCam16 *recastInVc = [MCUCam16 fromXyzInViewingConditions:MCUVecGet(viewedInVc, 0)
                                                            y:MCUVecGet(viewedInVc, 1)
                                                            z:MCUVecGet(viewedInVc, 2)
                                            viewingConditions:[MCUViewingConditions DEFAULT]];

  // 3. Create HCT from:
  // - CAM16 using default VC with XYZ coordinates in specified VC.
  // - L* converted from Y in XYZ coordinates in specified VC.
  return [MCUHct from:[recastInVc getHue]
               chroma:[recastInVc getChroma]
                 tone:[MCUColorUtils lstarFromY:MCUVecGet(viewedInVc, 1)]];
}

- (void)setInternalState:(int)argb {
  _argb = argb;
  MCUCam16 *cam = [MCUCam16 fromInt:argb];
  _hue = [cam getHue];
  _chroma = [cam getChroma];
  _tone = [MCUColorUtils lstarFromArgb:argb];
}

@end
