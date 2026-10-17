export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = LineageQSPrefs
LineageQSPrefs_FILES = LQSRootListController.m $(addprefix ../Sources/,LQSTheme.m LQSVectorIcon.m LQSStrings.m LQSMonet.m LQSWallpaper.m LQSColorsViewController.m) $(wildcard ../Monet/*.m)
LineageQSPrefs_FRAMEWORKS = UIKit CoreText CoreImage
LineageQSPrefs_PRIVATE_FRAMEWORKS = Preferences
LineageQSPrefs_INSTALL_PATH = /Library/PreferenceBundles
LineageQSPrefs_CFLAGS = -fobjc-arc -I../Sources -I../Monet
include $(THEOS_MAKE_PATH)/bundle.mk
