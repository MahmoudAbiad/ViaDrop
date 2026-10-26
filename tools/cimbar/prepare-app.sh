#!/usr/bin/env bash
# Reproducible binary inputs plus covered-source/notices for test APK distribution.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
: "${VIADROP_COLOR_DEPS:?Set an absolute dependency build directory}"
mkdir -p "$VIADROP_COLOR_DEPS"
revision=156fbb9c675ca9641f6559922b7025a0f2ee8125
source="$VIADROP_COLOR_DEPS/libcimbar"
if [ ! -d "$source/.git" ]; then
 git init -q "$source"
 git -C "$source" remote add origin https://github.com/sz3/libcimbar.git
 git -C "$source" fetch --depth 1 origin "$revision"
 git -C "$source" checkout --detach FETCH_HEAD
fi
test "$(git -C "$source" rev-parse HEAD)" = "$revision"
if [ ! -d "$VIADROP_COLOR_DEPS/OpenCV-android-sdk" ]; then
 curl --fail --location --retry 2 --output "$VIADROP_COLOR_DEPS/opencv.zip" \
  https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-android-sdk.zip
 echo "464d55abe64b53af3aeb73197cf4620535abd909916d06e6a8b7c32712013966  $VIADROP_COLOR_DEPS/opencv.zip" | sha256sum --check
 unzip -q "$VIADROP_COLOR_DEPS/opencv.zip" -d "$VIADROP_COLOR_DEPS"
fi
python3 "$root/tools/cimbar/prepare-app.py" "$root" "$VIADROP_COLOR_DEPS"
