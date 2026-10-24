#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
src="$repo/android/app/src/main/cpp"
for file in cyrinx_bulk.c cyrinx_fft.c kissfft/kiss_fft.c kissfft/kiss_fftr.c; do
  cc -std=c11 -O2 -fPIC -Dkiss_fft_scalar=double -I"$src/cyrinx/include" -I"$src/cyrinx/kissfft" -c "$src/cyrinx/$file" -o "$build/$(basename "$file").o"
done
c++ -std=c++17 -O2 -I"$src" -I"$src/cyrinx/include" "$repo/test/native/ofdm_stream.cpp" "$src/ofdm_codec.cpp" "$build/"*.o -lm -o "$build/stream"
"$build/stream"
cc -shared "$build/"*.o -lm -o "$build/codec.so"
python3 "$repo/tools/benchmark_ofdm.py" "$build/codec.so"
