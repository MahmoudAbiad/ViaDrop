#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
: "${ANDROID_HOME:?Android SDK path required}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 8 -target 8 \
 -bootclasspath "$ANDROID_HOME/platforms/android-23/android.jar" \
 -d "$work/classes" \
 "$root/components/color_codec/java/app/viadrop/color/ColorCodec.java" \
 "$root/components/color_codec/java/app/viadrop/color/Yuv420Rgb.java" \
 "$root/components/color_codec/android/app/viadrop/color/CameraImageDecoder.java" \
 "$root/components/color_codec/android/app/viadrop/color/ColorCameraSession.java" \
 "$root/components/color_codec/android/app/viadrop/color/ColorFrameRenderer.java" \
 "$root/android/app/src/main/java/app/viadrop/viadrop/ColorSessionState.java"
echo "PASS Android API23 Java color camera session compilation (not a runtime test)"
