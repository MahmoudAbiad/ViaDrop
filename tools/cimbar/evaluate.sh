#!/usr/bin/env bash
# Evaluation only. No installation into the Android application.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
revision=156fbb9c675ca9641f6559922b7025a0f2ee8125
git init -q "$work/source"
git -C "$work/source" remote add origin https://github.com/sz3/libcimbar.git
git -C "$work/source" fetch --depth 1 origin "$revision"
git -C "$work/source" checkout --detach FETCH_HEAD
test "$(git -C "$work/source" rev-parse HEAD)" = "$revision"
python3 - "$root/tools/cimbar/source.json" "$work/source" <<'PY'
import hashlib,json,pathlib,sys
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
source=pathlib.Path(sys.argv[2])
for name, expected in manifest['license_files'].items():
    actual=hashlib.sha256((source/name).read_bytes()).hexdigest()
    if actual != expected: raise SystemExit('License/source snapshot mismatch: '+name)
print('PASS pinned revision and license snapshot')
PY
cmake -S "$work/source" -B "$work/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
cmake --build "$work/build" --target encoder_test --parallel 2
# Synthetic color images only; no claims about real cameras or throughput.
"$work/build/build/src/lib/encoder/test/encoder_test" 'EncoderRoundTripTest/testFountain.Pad,EncoderRoundTripTest/testStreaming'
# Exercise ViaDrop's independent, file-free RGB adapter against the same pin.
cmake -S "$root/components/color_codec" -B "$work/adapter" -DCIMBAR_SOURCE="$work/source" -DCMAKE_BUILD_TYPE=Release
cmake --build "$work/adapter" --target color_adapter_test viadrop_color_jni --parallel 2
"$work/adapter/color_adapter_test"

mkdir -p "$work/classes"
javac -d "$work/classes" "$root/components/color_codec/java/app/viadrop/color/"*.java
java -Djava.library.path="$work/adapter" -cp "$work/classes" app.viadrop.color.CodecSmoke
java -cp "$work/classes" app.viadrop.color.YuvSmoke
