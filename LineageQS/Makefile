export THEOS_PACKAGE_SCHEME = rootless
export TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LineageQS
LineageQS_FILES = Tweak.xm $(wildcard Sources/*.m) $(wildcard Monet/*.m)
LineageQS_CFLAGS = -fobjc-arc -ISources -IMonet
LineageQS_FRAMEWORKS = UIKit CoreText CoreImage

SUBPROJECTS += Prefs lqsctl

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
