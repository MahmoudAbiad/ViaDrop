# CIMBAR integration checkpoint

Candidate revision: `156fbb9c675ca9641f6559922b7025a0f2ee8125` from
https://github.com/sz3/libcimbar . This is a reproducible evaluation, not an
Android integration or a completed license clearance.

## Dependency findings from source

| Component | License evidence inspected | Integration disposition |
| --- | --- | --- |
| libcimbar code | MPL-2.0 root LICENSE and file headers | Separate covered component; source availability, modifications and notices must be provided when distributing |
| libcorrect | BSD-3-Clause LICENSE | Retain notice; uses its own RS/convolutional code |
| wirehair / bundled gf256 | BSD-3-Clause LICENSE and gf256 file header | Retain both notices |
| zstd | BSD LICENSE and GPL alternative COPYING | Select BSD option; do not select GPL alternative |
| base91 | zlib-style permission in LICENSE | Preserve origin and modification notices |
| intx | Apache-2.0 LICENSE | Preserve license/required notices |
| libpopcnt | BSD-2-Clause LICENSE | Retain notice |
| concurrentqueue / fmt / PicoSHA2 | Individual license files captured in manifest | Complete inclusion/reachability review before shipping |
| stb | MIT / public-domain alternatives | Select MIT and preserve notice |
| Catch2 | Boost license header in test/catch.hpp | Evaluation-only test dependency |
| OpenCV | External host dependency, not part of vendored snapshot | Pin/review Android build configuration and included codecs separately |
| GLFW / GL | Host build prerequisites | Keep out of planned Android codec target unless actually required |

`tools/cimbar/source.json` records the inspected license-file SHA-256 values.
It is an inventory, not proof that every source file shares a root license.

## Evaluation

The dedicated workflow builds the pinned upstream `encoder_test` target and runs
its fountain padding and streaming round trips through actual colored images.
The upstream implementation is downloaded to a disposable build directory,
not copied into ViaDrop or relicensed. No user content is transmitted.
A successful result proves only host compilation and synthetic image decoding.
It does not prove on-phone CPU performance, optical robustness or patent clearance.

## Android boundary to implement after evaluation

- A dedicated native codec component, with its covered source and changes tracked.
- An original adapter with explicit image dimensions, row stride, RGB/YUV format,
  bounded allocations and a cancellation generation. JNI exceptions must not cross
  into Flutter unchecked.
- Camera pixel access is required: the existing MobileScanner barcode strings
  cannot decode CIMBAR. Do not advertise color support until pixel capture and
  both sender/receiver have been implemented and tested.
- Keep file acceptance, streaming storage, SHA-256 verification and consent in
  ViaDrop; do not use upstream filename-writing helpers on untrusted payloads.
- Publish the exact covered-source archive and notices alongside any distributed
  codec binary, and assess every selected dependency. Do not assume a wrapper
  removes license obligations. ViaDrop-specific independent files remain separate.

Primary license guidance: https://www.mozilla.org/en-US/MPL/2.0/FAQ/ .

## Recorded host result — 2026-10-25

GitHub Actions run https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40186728560
completed successfully for checkpoint a22f023. The pinned `encoder_test` executable
reported **17 assertions passed in 2 test cases**, covering fountain padding and
streaming via color images. No camera, Android device or throughput was tested.

Compiler/linker warnings require follow-up before shipping: an upstream test
helper uses `tmpnam`; the bundled zstd header/filename path triggered a GCC
`-Wstringop-overflow` warning after inlining. These warnings are not confirmed
exploitable vulnerabilities. Investigate with bounded malformed-input tests and
sanitizers; avoid importing the filename/decompression sink into ViaDrop. Prefer
updating or replacing the affected dependency/path with regression coverage.
No new APK contains CIMBAR at this checkpoint.

## RGB/JNI adapter result — 2026-10-26 (Asia/Damascus)

Run https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40246506269 passed for
32ba708. The original C++ adapter restored 1/100/4096-byte packets from
1024×1024 RGB images, including padded row strides. It rejected truncated and
invalid buffers. Java loaded the shared JNI library and passed the same packet
round trips and JNI malformed-input checks on the host JVM.

Fixes established by the regression runs: generate complete ECC data frames,
use the upstream-supported memory stream, and normalize non-contiguous RGB
rows before upstream cell readers traverse pixels. The application remains
separate from this MPL-2.0 component. This is not an Android ABI build, a camera
test, or an on-device throughput result. Android camera capture, YUV conversion,
rotation/lifecycle handling, cross-compilation and Flutter display remain pending.


## Android build checkpoint — 2026-10-26 (Asia/Damascus)

Run https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40250409302 passed both
Android cross-build jobs at dc19f23: ELF64/AArch64 and ELF32/ARM, with the expected
JNI encode/decode exports. Production Java adapters, including CameraImageDecoder,
compiled against android-23/android.jar with Java 8 bytecode compatibility.
OpenCV Android SDK 4.10.0 is checked against the upstream published SHA-256;
NDK 28.2.13676358 and the CIMBAR source revision remain pinned.

ARM32 initially failed with __tls_get_addr after upstream LTO. The Android
component now explicitly uses emulated TLS and disables upstream IPO for its
native object libraries, retaining ordinary Release optimization and thread-local
configuration. The resulting cross-build passed; on-device loading is untested.

The YUV converter covers plane offsets, row/pixel strides, truncated buffers,
limited-range BT.601/BT.709 selection and right-angle rotations. Its host tests
passed in run 40249613825; repeated host jobs may still be running independently
of the completed Android jobs above.

CameraImageDecoder accepts an acquired YUV_420_888 Image, performs conversion,
rotation and native decoding on a caller-supplied worker, and closes the Image
in finally. Non-full crops and unsupported matrices/formats must be handled
explicitly; there is no silent format substitution. Camera opening/session
management, bounded frame scheduling with cancellation generation, Flutter
rendering, packaging/notices and physical two-device tests are still pending.
No APK yet includes or advertises the color codec.


## Camera session and surface renderer implementation

The isolated component now implements Camera2 capture (`ColorCameraSession`)
and packet-to-Surface presentation (`ColorFrameRenderer`). The capture path has
separate camera/decode loopers, bounded Image ownership, frame dropping, stale
callback suppression and ordered asynchronous teardown. The sender provides
backpressure and reuses its bitmap/ARGB buffers; it requires at least 1024x1024
surface pixels and does not claim suitability for the J7 display.

The SDK23 compile check now runs independently of the slower native build.
Compilation does not validate actual Camera2 output combinations, color-space
selection, optics, lifecycle race behavior or on-screen readability. Flutter
platform channel/texture binding, permission flow, pause/resume, profile gating,
packaging and the dependency/source distribution bundle remain outstanding.
No color APK or two-phone test is available from this change.
