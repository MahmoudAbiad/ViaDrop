#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The local runtime has jdk.compiler even when the javac launcher is absent.
if command -v javac >/dev/null 2>&1; then
 compiler=(javac)
else
 compiler=(java -m jdk.compiler/com.sun.tools.javac.Main)
fi
"${compiler[@]}" -source 8 -target 8 -d "$work/classes" \
 "$root/android/app/src/main/java/app/viadrop/viadrop/NativeSessionState.java" \
 "$root/test/native/ColorSessionStateTest.java" \
 "$root/android/app/src/main/java/app/viadrop/viadrop/SessionWorkDrain.java" \
 "$root/test/native/AudioSessionDrainTest.java"
java -cp "$work/classes" app.viadrop.viadrop.ColorSessionStateTest
java -cp "$work/classes" app.viadrop.viadrop.AudioSessionDrainTest

# When the minimum Android platform is present, reject accidental newer Java
# library APIs as well as testing the host lifecycle behavior.
if [ -n "${ANDROID_HOME:-}" ] && [ -f "$ANDROID_HOME/platforms/android-23/android.jar" ]; then
 "${compiler[@]}" -source 8 -target 8 \
  -bootclasspath "$ANDROID_HOME/platforms/android-23/android.jar" \
  -d "$work/api23" \
  "$root/android/app/src/main/java/app/viadrop/viadrop/NativeSessionState.java" \
  "$root/android/app/src/main/java/app/viadrop/viadrop/SessionWorkDrain.java"
 echo 'PASS native application session owner compiles against API23'
fi
