# Isolated color codec boundary — experimental

This component is explicitly licensed MPL-2.0 (see LICENSE). It is separate
from the proprietary Flutter application. It builds against the exact CIMBAR
source pin audited in tools/cimbar/source.json, without copying upstream code
into ViaDrop application files. Full selected-dependency distribution review
remains necessary before any APK ships this component.

`codec.h` exposes caller-owned RGB buffers and packets up to 4096 bytes. The
VDCL frame wrapper carries length and CRC-32, not encryption. Feed encrypted
transfer packets into it; keep final authenticated verification in ViaDrop.
No upstream path-writing or zstd filename helpers are used by this adapter.
Rectified images must match the codec's exact geometry; camera images can use
the upstream extractor path. Bad data produces no output packet.

`ColorCodec.java` + `jni.cpp` provide the JNI boundary for later Android wiring.
Tests currently target host C++/JVM, not Android ABI or a physical camera. RGB
rows can be padded; YUV-to-RGB conversion, rotation, generation cancellation,
CameraX analysis and Flutter display remain to implement. Call on a bounded
worker; never on Flutter/Android UI thread. No color option is enabled in the app.

CI exercises binary packets, stride padding, malformed buffers and bounds.
Passing host tests does not establish camera robustness, transfer rate, Android
compilability or distribution clearance. The production Android CMake project
intentionally does not yet include this component.

`Yuv420Rgb` converts bounded planar/interleaved YUV420 buffers with explicit
row/pixel strides, buffer offsets, and 0/90/180/270-degree rotation. Matrix
selection is explicit (limited-range BT.601 or BT.709); the camera adapter must
supply the actual color space or reject unsupported/unknown data spaces. It is
not yet connected to an Android ImageReader/CameraX lifecycle. The input image
must remain open during conversion and be closed by the caller afterward.

The Android-specific `CameraImageDecoder` now accepts a real `android.media.Image`,
requires YUV_420_888, converts/rotates its planes and calls native extraction.
It closes the acquired image in a finally block, including on errors. Its source
is compiled against API23 separately from host-JVM tests. This is a per-image
adapter, not camera opening/session management or a Flutter screen. Capture
scheduling, cancellation generations, runtime permission and display integration
are still pending. It requires an explicit supported limited-range color matrix.
