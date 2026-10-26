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
 "$root/android/app/src/main/java/app/viadrop/viadrop/ColorSessionState.java" \
 "$root/test/native/ColorSessionStateTest.java"
java -cp "$work/classes" app.viadrop.viadrop.ColorSessionStateTest
