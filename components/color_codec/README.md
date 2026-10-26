# Isolated color codec boundary — experimental

This component is explicitly licensed MPL-2.0 (see LICENSE). It is separate
from the proprietary Flutter application. It builds against the exact CIMBAR
source pin audited in tools/cimbar/source.json, without copying upstream code
into ViaDrop application files. Full selected-dependency commercial release review remains a release gate.
Experimental APK builds retain original dependency notices and an exact covered-source artifact.

`codec.h` exposes caller-owned RGB buffers and packets up to 4096 bytes. The
VDCL frame wrapper carries length and CRC-32, not encryption. Feed encrypted
transfer packets into it; keep final authenticated verification in ViaDrop.
No upstream path-writing or zstd filename helpers are used by this adapter.
Rectified images must match the codec's exact geometry; camera images can use
the upstream extractor path. Bad data produces no output packet.

`ColorCodec.java` + `jni.cpp` provide the JNI boundary for later Android wiring.
Host C++/JVM tests are separate from the Android ARM32/ARM64 cross-builds.
Neither is a physical camera runtime test. RGB
rows can be padded; YUV-to-RGB conversion and rotation are implemented and tested separately.
Camera scheduling and generation cancellation are implemented in the Android
session below. Flutter display/session binding is implemented through the app ColorBridge. Never encode
or decode on the Flutter/Android UI thread. The app exposes an explicitly experimental qr-color option with role-specific gates.

CI exercises binary packets, stride padding, malformed buffers and bounds.
Passing host tests does not establish camera robustness, transfer rate, Android
compilability or distribution clearance. The Android app CMake project now includes this component when pinned inputs
are supplied by tools/cimbar/prepare-app.sh and configure-gradle.py.

`Yuv420Rgb` converts bounded planar/interleaved YUV420 buffers with explicit
row/pixel strides, buffer offsets, and 0/90/180/270-degree rotation. Matrix
selection is explicit (limited-range BT.601 or BT.709); the camera adapter must
supply the actual color space or reject unsupported/unknown data spaces. It is
connected through ColorCameraSession to a Camera2 ImageReader. The input image
remains open during conversion and CameraImageDecoder closes it afterward.

The Android-specific `CameraImageDecoder` now accepts a real `android.media.Image`,
requires YUV_420_888, converts/rotates its planes and calls native extraction.
It closes the acquired image in a finally block, including on errors. Its source
is compiled against API23 separately from host-JVM tests. This is a per-image
adapter, not a Flutter screen. It requires an explicit supported limited-range
color matrix.


## Android camera and display surfaces

`ColorCameraSession` owns Camera2 open/configure/repeating capture and a
YUV_420_888 ImageReader (three slots). Camera callbacks and decode use separate
HandlerThreads. At most one Image enters decoding; incoming excess frames are
closed, acquireLatestImage discards stale queued frames, and at most one packet
callback waits on the main thread. A session generation suppresses old results
on stop/restart, including results already posted to main. Stop does not
interrupt native decoding. Reader closure is queued after the worker releases
its Image. Disposal keeps the camera callback looper alive until pending opens
close their devices. Use close(onReleased) before releasing a preview Surface.

`ColorFrameRenderer` encodes actual packet bytes on a dedicated worker and draws
1024x1024 colored pixels onto a caller-owned Android Surface. It reuses one
bitmap and ARGB buffer, uses nearest/integer scaling, and rejects a surface
smaller than 1024 pixels on either axis. One frame may be outstanding, including
its main-thread completion; present(false) means busy, never delivered. Cancel
suppresses completion, but cannot undo a frame already posted to the surface.
Use close(onReleased) before releasing the caller Surface. An onPresented event
only means display submission, not successful reception or measured goodput.

These classes use only API23 interfaces and are checked in a dedicated quick
CI job before the native matrix completes. The Flutter/Android binding now supplies camera permission flow, output size,
sensor/display rotation, explicit user-selected color matrix and SurfaceTexture
ownership, and stops on app pause. Both classes are packaged in the test APKs. No physical device runtime result
is claimed, and lifecycle behavior still requires instrumented/device tests.


The app packaging step retains the official OpenCV SDK's supplied notices and
pinned NDK notices in Android and Flutter assets. The source archive includes
this complete component, pinned libcimbar source, build tools and notices. The
application's independent proprietary source is not part of that covered-source
archive. SDK notice retention is not a blanket legal clearance for all product
dependencies; see the project's release audit gate.
