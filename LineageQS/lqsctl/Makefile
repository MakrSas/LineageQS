export THEOS_PACKAGE_SCHEME = rootless
# CLI processes use the stable arm64 ABI, including on arm64e devices.
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TOOL_NAME = lqsctl
lqsctl_FILES = main.m
lqsctl_CFLAGS = -fobjc-arc
lqsctl_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
