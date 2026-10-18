# 0.4.14 changes and verification

## Changes

- Document the existing iOS 15.0 deployment target separately from the iOS 16.5
  SDK, declare the minimum firmware dependency, and add the older CoreDuet
  battery-saver fallback. This does not establish full iOS 15 runtime support.
- Share accepted tile/detail toggle requests until hardware acknowledges them.
  Poll every 250 ms, allow reversal, and fall back to actual state after eight
  seconds. Bluetooth/Wi-Fi no longer immediately revert during radio startup.
- Load the ReplayKit Control Center bundle before installing recording hooks.
  Observe recording state without replacing native delegates. Add a cancellable
  3-2-1 countdown in the recording icon that survives shade dismissal, plus a
  red QS clock with a stop-recording confirmation. Leave tap-like status-bar
  activity gestures to iOS rather than routing them into QS.
- Resolve notification app names through SpringBoard/Launch Services when the
  notification header is absent or contains a bundle ID. Cache by language and
  use a localized fallback for sections without an installed app.
- Keep the notification dark surface full-height during opening, independently
  of the content reveal. Preserve native gesture routing, settling timing, the
  original composed QS tint and activated tile radii. Fade native system blur
  with runtime-checked material weighting, falling back to native view alpha;
  hide it at zero presentation progress. Preview blur remains separate.
- Size small tiles and editor previews square on narrow screens. Fit grid rows
  above a bottom-anchored pager/Edit footer and Settings/Power row, respecting
  bottom and horizontal safe-area insets.
- Add an optional, default-off Home Screen notification gesture in Settings >
  LineageQS > Gestures. A continuous downward pan drives the native interactive
  presenter, starting in compact notification mode. Spotlight waits for this
  gesture; direction uses displacement rather than speed for slow pulls.
  Exclude widgets/Smart Stacks, Today View, App Library, controls, editing,
  open folders and page transitions. Preferences apply live.
- Make the build script Bash-compatible, normalize shell/Debian metadata to LF,
  and add a project-local Linux toolchain helper. Build arm64/arm64e dylibs and an
  arm64 CLI; apply pinned static arm64e ABI conversion and re-sign on Linux.

## Build and automated checks

```sh
bash scripts/build-linux.sh
cc -std=c11 tests/panel_layout.c -lm -o /tmp/lqs-layout
/tmp/lqs-layout
```

The Linux helper uses the toolchain recommended by the
[Theos installer](https://github.com/theos/theos/blob/master/bin/install-theos)
without replacing an existing Theos installation. It pins
[allemande](https://github.com/p0358/allemande) for static conversion following
the [Theos rootless guide](https://theos.dev/docs/rootless). No system-wide
`oldabi` dependency is added.

The footer regression checks cover SE-sized and notched portrait/landscape
viewports, bottom anchoring, row fitting and a height/safe-area sweep. Package
inspection checks minimum iOS 15.0, arm64/arm64e dylibs, the arm64 CLI and signed
code-page hashes. Plists and the new preference default/notification are checked
separately. These checks do not validate private API behavior on a phone.

## On-device checks

Runtime validation remains necessary on iOS 15/16 and an arm64e device:

1. Toggle Bluetooth/Wi-Fi from tiles and details. Confirm startup state,
   rapid reversal, external changes and failed-request rollback.
2. Check recording 3-2-1, countdown cancellation, shade dismissal, recording
   started/stopped outside QS, tile state, native status-bar stop, and the red
   QS clock's stop/cancel confirmation.
3. Check app names for installed, removed and system notification sections,
   including after changing the phone language.
4. Open/close with slow drags, holds, flicks, cancellation and immediate reversal.
   Check the full-height dark surface, native blur fade, split/top/bottom routes,
   rotation, Reduce Motion and Reduce Transparency.
5. On SE-sized screens, check circles, original activated radii, footer buttons,
   pager/Edit, tile editor, pagination and rotation.
6. Toggle off: retain Spotlight. Toggle on: check very slow pulls, short releases,
   pull-back cancellation, and reopening from previously expanded QS. Confirm
   App Library, Today View, widgets, Smart Stacks, horizontal paging, search
   buttons, folders and editing retain native gestures. Test live toggle/master
   disable.

## Private API references

Existing device probes remain the primary evidence for the integration path.
Newer runtime headers are supporting references only, not proof that iOS 15/16
has identical behavior; optional selectors are guarded at runtime.

- [ReplayKit recording state](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/Frameworks/ReplayKit.framework/RPScreenRecorder.h)
- [Native material weighting](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/MaterialKit.framework/MTMaterialView.h)
- [Home Screen page state](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBRootFolderView.h)
- [Search failure dependency](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBSearchGesture.h)
- [Continuous pan recognizer](https://developer.apple.com/documentation/uikit/uipangesturerecognizer)
