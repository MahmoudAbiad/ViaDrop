# Validation

## Automated simulation

- `recovery_test.dart`: state transitions, unsafe names, AES-GCM round trip,
  incorrect password, modified ciphertext and cleanup.
- `physical_roundtrip_test.dart`: loss/duplicates, batch QR capture, corrupt payload,
  encrypted envelope through fountain packets, session binding, Base45, and
  legacy X25519 crypto tests.
- `one_way_session_test.dart`: one-way invitation parsing, independent keys,
  malformed starts, session filtering and encrypted fountain reconstruction.
- `physical_profiles_test.dart`: implemented/disabled profile checks, probe
  failures, automatic local recommendation, and VDS3 mode agreement.
- `physical_profile_selector_test.dart`: disabled dropdown entries.
- `qr_profile_capacity_test.dart`: QR v13/v17 encoded fountain frames fit.
- `physical_receive_metrics_test.dart`: goodput and frame counters.
- Actual RX payload goodput and accepted/rejected frame counts are displayed
  after a verified transfer. They do not include initial pairing or decryption
  time, and do not reveal missing over-the-air frames.
- Physical device probe and transport settings require on-device tests; CI
  simulation does not establish real cross-device codec performance.
- `lan_integration_test.dart`: local host HTTP consent/streaming/error scenarios.
- `native/audio_loopback.cpp`: actual ggwave PCM encode/decode at 48 kHz signed
  16-bit mono, audible-fast and ultrasound-fast, 64/132/140-byte packets, with
  silence and deterministic low-amplitude additive noise. The 132-byte case
  covers the current 100-byte fountain payload plus 32-byte header.

These are simulations. They do not test a real camera, Android microphone,
acoustic echo, device permissions, Bluetooth radios or speaker frequency response.
The baseline c3de76f had successful legacy/modern CI runs; each new commit needs
its own test/build results in GitHub Actions.

## Required two-device tests — NOT EXECUTED here

Use Samsung J7/Android 6 ARM32 and a modern ARM64 phone. Record both model/OS,
commit, APK hash, channel, mode, input/output SHA-256, elapsed time and outcome.

1. QR: airplane mode, radios off. Show a static one-way start QR on sender;
   scan it once with the receiver. Wait before pressing Start, then verify the
   sender's 3-second countdown and automatic switch to fountain QRs. Test
   empty files, Arabic text/names, image, PDF, random bytes, missing frames,
   stop/restart and fast mode. No response scan or confirmation is expected.
   Never accept partial output.
2. Audio: airplane mode, radios off. Start receiver first: it must listen
   silently with **no playback**. Sender then emits start announcement(s) and
   file data. Verify no receiver sound during any phase. Begin with short text,
   then binaries and larger files. Test both slow/fast data paths and volume/
   noise/placement conditions. Old and new APKs are not interoperable.
   - Block first ggwave announcement, then restore audio proximity. Confirm
     another announcement is sent after 24 data frames and receiver can join.
   - Stop/restart while sending start tones, during OFDM data, during decoding,
     or while finalizing. Check no orphan microphone or stale playback.
   - Confirm a second unrelated session's data cannot contaminate an active
     receiver session, and AES-GCM and SHA-256 verify the final file.
   - Receiver sends no ACK; sender must be stopped manually after verifying
     success on the receiver.
3. Protocol/security: malformed VDS3 QR/audio announcements are rejected.
   An observer who captured VDS3 can decrypt this intentionally public-key
   announcement; explicitly warn users not to send sensitive files. Legacy
   X25519 unit tests are retained but no longer drive either physical UI.
4. LAN: offline router, accept/reject, multiple files, large-file memory use,
   interrupted connection, bad digest, filename traversal and output cleanup.
5. Bluetooth: secure paired RFCOMM, permission denial, rejection, interruption,
   repeated sessions, correct progress and output hashes.
6. All: background/foreground, navigation away, screen lock, cancellation during
   preparation/verification, temp cleanup, empty files and insufficient storage.

No physical completion rate or measured on-device throughput is available yet.

## Physical profile compatibility (new)

See [docs/PHYSICAL_PROFILES.md](docs/PHYSICAL_PROFILES.md). Test each transfer
with the same exact profile on both phones, then deliberately choose a mismatch:
QR should refuse the start while retaining its scan screen, and acoustic should
stop listening and show the sender's profile. Newly built VDS3 APKs cannot
interoperate with old VDS2 builds. Planned modes remain disabled even on
top-end phones. Probe results are only preliminary hardware evidence.

## Fast-audio implementation checkpoint

`bash tools/test_ofdm.sh` builds the exact vendored C codec and original C++
streaming adapter. Local simulation passed: nine OFDM configurations/noise/echo
cases and two four-packet unaligned PCM16 streams (clean and noise plus a 5 ms
20% echo). Every decoded packet matched the original bytes; the receiver requires
all CRC blocks to pass before releasing a packet. It buffers at most 65,536
samples and Android queues at most 48 PCM reads, discarding a backlog on overload.

The selected profile is 16-QAM rate 1/2, 1.1–16 kHz, 48 kHz mono: 1,024 modem
bytes per 0.6613-second waveform, carrying a 900-byte fountain block plus framing.
The 180 ms gap and fountain overhead reduce useful throughput. A 48 KiB input
is estimated around 1–2 minutes plus start announcements under favorable conditions;
this is NOT a device benchmark or upper bound. Slower mode remains explicit.
Both phones must select the same mode. Fast mode is audible only.

Physical tests must now additionally exercise Android CPU load/backlog behavior,
room echo, frequency response, microphone gain and sample-clock drift. These
were not modeled comprehensively by the deterministic simulation.

## Ultra receiver regression coverage

`ultra_reconstruction_test.dart` exercises the complete Base45 → packet CRC →
fountain reconstruction path with 2400-byte blocks, including a 512 KiB payload,
late join, 25% frame loss, duplicate/reordered frames and corrupted packets.
It also covers oversized Base45/base64 input rejection and subsequent valid input.
These simulations do not establish optical throughput or camera readability.


## Isolated color camera/display checkpoint — 2026-10-26

At 70b178a, the API23 camera session and surface renderer compile check passed
in Actions run https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40251853246
(job android-camera-api23). This compiles against Android 6 framework classes;
it does not run Camera2 or draw to a real Android Surface. YuvSmoke also passed
locally using the JDK compiler module and JVM: stride/offset/rotation/matrix and
truncated-plane cases. The unchanged native/host matrix has its own job results.

New device/instrumentation cases, all **not executed**:

- Start, stop during asynchronous open, immediately restart, then dispose;
  verify camera availability afterward and no stale packet/ready callbacks.
- Cancel during native extraction; verify Image closes before ImageReader and
  close(onReleased) runs only after camera/device/image resources are released.
- Keep main thread busy while capturing; verify at most one packet event waits
  and one image decodes, without ImageReader exhaustion or growing frame queues.
- Detach preview, deny/revoke permission, occupy camera in another app, inject
  disconnect/configuration failure, and background/foreground repeatedly.
- Encode known binary packets to a real Surface, verify visible frame geometry
  and payload decoding on the other phone with matching mode/matrix/orientation.
- Submit frames faster than encoding/display; busy requests must return false,
  never successful delivery. Cancel/dispose during encode or canvas submission;
  release Surface only from the cleanup callback.
- Reject sub-1024 surfaces; measure memory/CPU/thermal behavior and actual verified
  payload goodput. Test Android6 and modern Android separately where compatible.

That isolated checkpoint is superseded by the application integration below;
its device/instrumentation cases remain unexecuted.


## Color application integration — 0.3.0

Implemented code is now linked into both APK build profiles, with a Flutter
texture sender, native Camera2 receiver, binary packet event channel and the
existing fountain/AES-GCM/SHA-256 reconstruction path. Role-specific capability
checks permit an eligible small-screen phone to receive while requiring a
1080px screen to send. MobileScanner relinquishes the opening-QR camera before
the native receiver opens it. No network or Bluetooth carrier is present in the
color data path.

Verified at 3260ca5: both complete APK workflows passed (modern run 40253166435,
Android6 run 40253166401), including 44 Dart tests and analysis. Artifact inspection
confirmed the color JNI library, retained JNI class name, Android/Flutter notice
assets and 16KB ELF load alignment. Later source revisions add full-HD stream
selection, direction-specific gating, NDK notice retention and APK signature
verification; final run results are recorded in docs/CIMBAR_INTEGRATION.md.

Color evaluation run 40254519362 at 0d3486b passed all jobs: host round trips,
Android ARM32/ARM64 cross-builds and the API23 camera/display compile check.
The host suite includes real packet bytes encoded as colored RGB images,
synthetic YUV420 subsampling with BT.601 and BT.709, conversion back to RGB,
and native packet reconstruction. A 1280x1280 synthetic scene also passed
unrectified extraction. This validates that pixel pipeline, not an optical
link between physical devices.

No physical Android installation, camera/speaker loopback or two-phone transfer
was executed. CPU, thermal, battery and sustained goodput are unmeasured. Follow
[the device procedure](docs/COLOR_DEVICE_TEST.md) before claiming device support.


Final 0d3486b integration result: both APK runs 40254519430 / 40254519498 passed
all tests, analysis, release build, minSdk/ABI/native/notice checks and official
APK signature verification. APK artifact checksums and post-download inspection
are recorded in docs/CIMBAR_INTEGRATION.md. This does not change the unexecuted
physical-device test statuses above.


## 0.3.1 lifecycle regressions

See [docs/LIFECYCLE_0_3_1.md](docs/LIFECYCLE_0_3_1.md) for concrete triggers,
ownership rules and coverage. The host native-state test passed locally,
including 10,000 lifecycle cycles and 20,000 exactly-once cleanup replies.
It does not open a camera, microphone or Android Surface. Automated APK build
and Dart suite results for the final code revision are recorded separately.
No physical-device acceptance status changes as a result of these simulations.


Final 0.3.1 result at 7fa9833: modern run 40270106347 and Android6 run
40270106323 both passed 56 Flutter tests, analysis, native lifecycle simulations,
release APK build and official signature verification. The host simulation
completed 10,000 lifecycle cycles / 20,000 exactly-once stop replies. Native
API23 compilation also passed in evaluation run 40269565499 at ceb62d6; native
ownership source is unchanged in the final app revision. These automated
results do not change the unexecuted physical-device statuses above.


## 0.3.2 acoustic lifecycle regressions

The real native ownership/worker-barrier classes are exercised by
`bash tools/test_native_lifecycle.sh`; the old test_color_lifecycle.sh command
is a compatibility wrapper. Local host simulation passed both the existing
10,000 session cycles and 10,000 two-worker acoustic cleanup cycles. Native
ownership helpers additionally compile against API23 when that platform is
installed. This does not instantiate Android audio hardware.

See [the acoustic report](docs/AUDIO_LIFECYCLE_0_3_2.md) for permission, queued
work, event identity and real-file/isolate cancellation tests. Final complete
APK/analysis/test results are recorded with their exact source revision below.
Physical acoustic acceptance remains unexecuted.


Final acoustic hardening result at 8f85eef: modern run 40275135298 and Android6
run 40275135371 both passed 66 Flutter tests, analysis, native ownership/drain
simulations and release APK/signature checks. The suite includes real encryption
and verification in isolates with cancellation/disposal checks, plus mocked
permission, native readiness, playback and event-identity cases. Generic state
and acoustic worker-drain models each exercised 10,000 cycles. No handset
installation, microphone/speaker loopback or two-phone transfer was performed.
See docs/AUDIO_LIFECYCLE_0_3_2.md and docs/BUILD_0_3_2.json for evidence.
