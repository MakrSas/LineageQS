#!/bin/zsh
# Theos rejects paths with spaces: build in ~/.lineageqs-build, copy the .deb back.
set -e
export THEOS=${THEOS:-$HOME/theos}
SRC="$(cd "$(dirname "$0")" && pwd)"
RES="$SRC/../Resources"
BUILD="$HOME/.lineageqs-build"
mkdir -p "$BUILD"
rsync -a --delete --exclude .theos --exclude packages "$SRC/" "$BUILD/"
mkdir -p "$BUILD/layout/Library/Application Support/LineageQS"
rsync -a --delete "$RES/vectors" "$RES/fonts" "$RES/strings" "$RES/colors.json" "$RES/battery_glyphs.json" "$RES/monet_table.bin" "$RES/monet_tokens.txt" "$BUILD/layout/Library/Application Support/LineageQS/"
cd "$BUILD"
rm -rf packages; make clean package FINALPACKAGE=1
mkdir -p "$SRC/packages"
cp packages/*.deb "$SRC/packages/"
ls -la "$SRC/packages"
