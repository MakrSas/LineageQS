#!/bin/sh
# Builds the preview host for the iOS Simulator into host/build/LineageQSHost.app
set -e
cd "$(dirname "$0")"
ROOT=..
APP=build/LineageQSHost.app
rm -rf "$APP"; mkdir -p "$APP/LineageQS"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -fobjc-arc -fmodules -target arm64-apple-ios15.0-simulator -isysroot "$SDK" \
  -I "$ROOT/LineageQS/Sources" -I "$ROOT/LineageQS/Monet" main.m "$ROOT"/LineageQS/Sources/*.m "$ROOT"/LineageQS/Monet/*.m \
  -framework UIKit -framework CoreText -framework CoreImage -o "$APP/LineageQSHost" -Wall -Wno-unused-variable
cp Info.plist "$APP/Info.plist"
cp -R "$ROOT/Resources/vectors" "$ROOT/Resources/fonts" "$ROOT/Resources/strings" "$ROOT/Resources/colors.json" "$ROOT/Resources/battery_glyphs.json" "$ROOT/Resources/monet_table.bin" "$ROOT/Resources/monet_tokens.txt" "$APP/LineageQS/"
codesign -s - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
