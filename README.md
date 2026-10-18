# LineageQS

The Android 17 (LineageOS 24) notification shade and Quick Settings for jailbroken iOS 15/16 (rootless, device-tested on iPhone 8, iOS 16.7; iOS 15 runtime validation still needed).
It replaces the Control Center view, and a swipe from the top opens it.

- Quick Quick Settings with notifications below; drag down to expand into full Quick Settings, which add brightness, a paged grid and footer actions.
- Tiles with real actions: Wi‑Fi/Internet, Bluetooth, mobile data, DND, flashlight, airplane, rotation, battery saver, dark theme, Night Shift, inversion, screen recording, Wallet/alarm/QR/Home.
- Android 17 tile editor: select, resize, drag, add/remove, undo, reset.
- Notifications grouped by app: swipe to dismiss, clear all, expandable stacks.
- Media player with the Android squiggly seek bar and the play/pause morph.
- Android 17 battery and status icons, Google Sans Flex.
- Colours from [Material You](https://github.com/MakrSas/MaterialYou) (required package).

Visual tokens, animations and behaviour come from the AOSP / LineageOS sources. Values are referenced in comments, `docs/` lists the research.

## Home Screen gesture

Settings > LineageQS > Gestures > **Home Screen swipe down opens notifications**
is off by default and applies immediately. When enabled, a downward drag on an
icon page opens compact notifications interactively instead of Spotlight.
App Library, Today View, widgets/Smart Stacks, editing and open folders are excluded.

## Build
- Theos with the iOS 16.5 SDK.
- Deployment target: iOS 15.0. The SDK version is not the minimum supported OS; optional private APIs are resolved at runtime.
- `LineageQS/build.sh` builds the tweak.
- On x86_64 Linux, `bash scripts/build-linux.sh` downloads the iOS toolchain recommended by Theos into `.build-tools/` without sudo (~620 MB download). To reuse an existing toolchain, set `SDKBINPATH` to its `bin` directory. It then builds pinned [allemande](https://github.com/p0358/allemande), statically converts the arm64e Obj-C ABI, and re-signs the packaged binaries. No system-wide `oldabi` dependency is needed; arm64e runtime testing is still required.
- `host/build-sim.sh` builds a simulator preview app.

## Verification

Run the portable footer/safe-area regression checks with:

```sh
cc -std=c11 tests/panel_layout.c -lm -o /tmp/lqs-layout
/tmp/lqs-layout
```

See [0.4.14 changes and on-device checks](docs/fixes-0.4.14.md) for the
remaining iOS 15/16 runtime verification.

## Safety
- Off by default.
- Kill switch: `lqsctl disable`, or create `/var/mobile/Library/LineageQS/DISABLE`.
- A boot-loop guard disables the tweak after repeated crashes.

Apache License 2.0, see NOTICE.
