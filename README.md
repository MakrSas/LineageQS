# LineageQS

The Android 17 (LineageOS 24) notification shade and Quick Settings for jailbroken iOS 16 (rootless, tested on iPhone 8, iOS 16.7).
It replaces the Control Center view, and a swipe from the top opens it.

- Quick Quick Settings with notifications below; drag down to expand into full Quick Settings, which add brightness, a paged grid and footer actions.
- Tiles with real actions: Wi‑Fi/Internet, Bluetooth, mobile data, DND, flashlight, airplane, rotation, battery saver, dark theme, Night Shift, inversion, screen recording, Wallet/alarm/QR/Home.
- Android 17 tile editor: select, resize, drag, add/remove, undo, reset.
- Notifications grouped by app: swipe to dismiss, clear all, expandable stacks.
- Media player with the Android squiggly seek bar and the play/pause morph.
- Android 17 battery and status icons, Google Sans Flex.
- Colours from [Material You](https://github.com/MakrSas/MaterialYou) (required package).

Visual tokens, animations and behaviour come from the AOSP / LineageOS sources. Values are referenced in comments, `docs/` lists the research.

## Build
- Theos with the iOS 16.5 SDK.
- `LineageQS/build.sh` builds the tweak.
- `host/build-sim.sh` builds a simulator preview app.

## Safety
- Off by default.
- Kill switch: `lqsctl disable`, or create `/var/mobile/Library/LineageQS/DISABLE`.
- A boot-loop guard disables the tweak after repeated crashes.

Apache License 2.0, see NOTICE.

## roothide branch

This branch builds for roothide (Procursus roothide, Nyxian "Procursus Jailed"):
build as usual with `build.sh`, then `scripts/roothide.sh packages/<pkg>_iphoneos-arm64.deb`
produces the `iphoneos-arm64e` package.
In the jailed ROM there is no Control Center: the shade opens with a downward
swipe anywhere on the home screen and is enabled by default.
