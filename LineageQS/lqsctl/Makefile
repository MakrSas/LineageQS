export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
TOOL_NAME = lqsctl
lqsctl_FILES = main.m
lqsctl_CFLAGS = -fobjc-arc
lqsctl_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
