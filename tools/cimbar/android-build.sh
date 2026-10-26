#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
abi=${1:?Pass ABI}
case "$abi" in arm64-v8a|armeabi-v7a) ;; *) exit 2;; esac
: "${ANDROID_NDK_ROOT:?Android NDK path required}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
revision=156fbb9c675ca9641f6559922b7025a0f2ee8125
git init -q "$work/source"
git -C "$work/source" remote add origin https://github.com/sz3/libcimbar.git
git -C "$work/source" fetch --depth 1 origin "$revision"
git -C "$work/source" checkout --detach FETCH_HEAD
curl --fail --location --retry 2 --output "$work/opencv.zip" \
 https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-android-sdk.zip
# Hash published by the OpenCV maintainers on the 4.10.0 release page.
echo "464d55abe64b53af3aeb73197cf4620535abd909916d06e6a8b7c32712013966  $work/opencv.zip" | sha256sum --check
unzip -q "$work/opencv.zip" -d "$work"
cmake -S "$root/components/color_codec" -B "$work/build" \
 -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
 -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-23 -DANDROID_STL=c++_shared \
 -DCIMBAR_SOURCE="$work/source" \
 -DOpenCV_DIR="$work/OpenCV-android-sdk/sdk/native/jni" \
 -DOpenCV_STATIC=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$work/build" --target viadrop_color_jni --parallel 2
lib="$work/build/libviadrop_color_jni.so"
test -s "$lib"
readelf="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
"$readelf" --file-header "$lib"
"$readelf" --dyn-syms "$lib" > "$work/symbols.txt"
grep -F 'Java_app_viadrop_color_ColorCodec_encode' "$work/symbols.txt"
grep -F 'Java_app_viadrop_color_ColorCodec_decode' "$work/symbols.txt"
echo "PASS Android native color codec cross-build: $abi (not a device runtime test)"
