# Acoustic session reliability — 0.3.2

This milestone changes lifecycle/ownership and cancellation, not the acoustic
wire format, transfer limit or advertised bitrate. It adds no third-party codec
or dependency. Existing 0.3.0 and 0.3.1 downloads remain unchanged.

## Implemented behavior

- `AudioClient` assigns an identity before permission or native startup. A late
  permission grant cannot open a cancelled microphone. Every native start,
  packet and stop belongs to one acoustic operation, not a global stop switch.
- `AudioBridge` owns a dedicated method/event channel. Bluetooth errors cannot
  be mistaken for acoustic errors. Shared observation routes packets by client
  and native generation; stopped clients reject delayed callbacks.
- Sending opens no microphone and requests no microphone permission. A listening
  native session rejects playback. The receiver remains acoustically silent.
- The original color session arbitrator is now named `NativeSessionState` and
  is shared by both bridges. Rejected starts do not acquire or abort an active
  session. Old cleanup cannot stop a newer client's session.
- A session registers every worker before enqueueing it. `SessionWorkDrain`
  completes cleanup only after the reader, OFDM decoder or queued encoder has
  executed its finally/release path. Duplicate stops join that same cleanup.
- PCM I/O uses API23 nonblocking short-array operations. Workers exclusively own
  AudioRecord/AudioTrack and codec handles, including stop/release/free. The UI
  only signals cancellation and waits for the worker barrier; it never frees an
  object while a worker still uses it.
- The executor has three maximum workers, a four-entry queue and a 15-second
  idle-thread timeout. OFDM PCM backlog remains bounded at 48 entries; overload
  drops backlog instead of allowing unbounded growth. Playback/write and
  microphone-start/no-PCM errors have explicit failure paths.
- Android pause/disposal stops current acoustic hardware. Flutter also cancels
  pending permission, preparation and playback, and prevents late UI updates.
- Once fountain reconstruction finishes, capture drains before file decryption.
  File verification uses its own manager token; stopping the now-unneeded
  microphone does not invalidate an otherwise complete file.
- Text-note staging and encrypted temporary files are removed on all send exit
  paths. The original selected file is retained, and text whitespace is preserved.

## Isolated file work

TransferManager captures the operation token across each isolate task. Closing
its route or replacing its operation rejects stale encryption/verification
results and removes their generated output. Isolate closures contain only path
and password strings, not the notifier or route callbacks. Disposal cancels its
operation and suppresses subsequent listener notifications.

Crypto work already running is not forcibly interrupted; cancellation prevents
publication when it returns. After authentication/integrity verification and
entry into the history commit, the valid saved file is retained even if the
screen closes during that commit. This commit boundary avoids deleting a
successfully verified file while leaving a saved history record pointing at it.
Cross-manager concurrent history persistence still needs its separate audit.

## Automated regression coverage

- AudioClient tests: stop before permission grant, denied permission, late native
  readiness, cancellation during playback, joined stop completions, old/new
  event identities, and authoritative native background cancellation.
- Real file/isolate tests: disposal during encryption, replacement by a newer
  operation, and disposal during verification. They check generated-file cleanup,
  original-file preservation and absence of accepted-file/history publication.
- Host Java tests exercise the actual native ownership and worker-drain classes:
  microphone/decoder release ordering, queued encode cancellation, duplicate or
  foreign job completions, joined stops and safe restart. They simulate 10,000
  acoustic two-worker teardown cycles, in addition to the existing 10,000
  generic session cycles. These tests do not use Android audio hardware.
- Existing native ggwave/OFDM PCM simulations remain in the modern APK workflow.

Primary Android references used for the API23 I/O boundary:
https://developer.android.com/reference/android/media/AudioTrack
https://developer.android.com/reference/android/media/AudioRecord

## Physical acceptance remains unexecuted

No Android handset is attached. Actual microphone/speaker creation, stop latency,
permission/back-stack behavior on Samsung firmware, Bluetooth-headset routing,
interruption by other audio apps, sustained CPU/memory use and phone-to-phone
transfers require hardware testing. Host tests and APK builds do not establish
J7/A24 compatibility or measured acoustic throughput. Acoustic modes retain their
48 KiB input / 64 KiB encrypted limits and one-way start announcement.


## Recorded result — 2026-10-26 (Asia/Damascus)

Final application revision: 8f85eefa6a1c6db36efea2f23e59c2921d294588.
Both complete workflows passed 66 Flutter tests, static analysis, native lifecycle
simulations, release compilation, minSdk/ABI/native/notice checks and official
APK signature verification:

- Modern ARM64 / API24+: https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40275135298
- Android6 ARM32 / API23+: https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40275135371

The modern APK verifies with v2 signing; legacy verifies with v1 and v2.
These are internal-test signing identities. App APK compilation/signature
verification does not constitute installation or an audio-driver runtime test.
The unchanged native component and Java ownership/drain helpers also passed
the separate evaluation at c607869 (run 40273459880), including the helper API23
boot-classpath check. That check is not a Kotlin audio hardware execution test.

The generated 0.3.2 APKs are available in those runs. Earlier delivered 0.3.0
files and the previous 0.3.1 build records were not replaced. BUILD_0_3_2.json
records exact provenance; its digests identify artifact ZIPs, not locally
recomputed standalone APK digests. Physical acceptance above remains unexecuted.
