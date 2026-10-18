#!/usr/bin/env bash
# Use the arm64e-capable toolchain recommended by the Theos installer, locally
# to this project. Do not replace the user's existing Theos installation.
set -euo pipefail
export THEOS="${THEOS:-$HOME/theos}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tools="$root/.build-tools"
export SDKBINPATH="${SDKBINPATH:-$tools/linux/iphone/bin}"
if [[ ! -x "$SDKBINPATH/clang" ]]; then
    if [[ "$(uname -m)" != x86_64 ]]; then
        echo "Set SDKBINPATH to a modern iOS toolchain for this host architecture." >&2
        exit 1
    fi
    mkdir -p "$tools/downloads"
    archive="$tools/downloads/swift-5.8.tar.xz"
    if [[ ! -f "$archive" ]]; then
        curl -fL --retry 2 \
            https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz \
            -o "$archive.partial"
        mv "$archive.partial" "$archive"
    fi
    tar -xJf "$archive" -C "$tools"
fi
export TARGET_CC="$SDKBINPATH/clang -target arm64-apple-ios15.0"
export TARGET_CXX="$SDKBINPATH/clang++ -target arm64-apple-ios15.0 -fuse-ld=$SDKBINPATH/ld"
export TARGET_LD="$TARGET_CXX"
bash "$root/LineageQS/build.sh"

# Open-source Linux toolchains still emit the old arm64e Obj-C ABI, even with
# modern Clang. Convert statically as recommended by the Theos rootless docs;
# this project contains no Swift/Cephei code and needs no system-wide oldabi.
converter="$tools/allemande/allemande"
if [[ ! -x "$converter" ]]; then
    if [[ ! -d "$tools/allemande/.git" ]]; then
        git clone https://github.com/p0358/allemande.git "$tools/allemande"
    fi
    git -C "$tools/allemande" checkout 43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9
    c++ -std=c++20 -O2 -o "$converter" "$tools/allemande/main.cpp"
fi
signer="$THEOS/toolchain/linux/iphone/bin/ldid"
package_version="$(awk '/^Version:/ {print $2}' "$root/LineageQS/control")"
package="$root/LineageQS/packages/com.makr.lineageqs_${package_version}_iphoneos-arm64.deb"
python3 "$root/scripts/convert-linux-package.py" "$package" "$converter" "$signer"
