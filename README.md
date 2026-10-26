# ViaDrop

**Share beyond connections. — شاركها بأي طريقة.**

Experimental Android Flutter/Dart application with Kotlin, native ggwave/OFDM audio and an isolated CIMBAR color codec.
The owner authorized public repository visibility; ViaDrop remains proprietary.
Third-party components retain their respective licenses.

## Active development

`main` is the active branch (owner instruction, 2026-10-24). It contains the
complete history previously developed on `recovery-dev`; that branch is retained
unchanged. This is an internal test application, not a production release.

Implemented paths:
- Wi-Fi LAN discovery, consent and streaming encrypted HTTP file transfer.
- Bluetooth Classic RFCOMM between paired devices, consent and acknowledgement.
- Camera-only Base45 QR frames: **one static start QR** on the sender; scan it
  once on the receiver, then manually start a three-second countdown before
  animated data QRs. No return scan, network, or acknowledgement.
- Experimental CIMBAR color pixels: the same static QR start, followed by
  actual encrypted fountain packets encoded into colored screen images.
  Camera2 YUV frames are decoded natively; reconstructed bytes use the existing
  integrity/authenticated file-verification path. No network or radio fallback.
- Speaker-to-microphone audio: **sender broadcasts** a ggwave start message
  followed by OFDM (or slower ggwave) file frames. The receiver only listens,
  with no reply, pairing tones or fingerprint step. Starts repeat if lost.
- AES-GCM file envelopes, SHA-256 verification, safe output filenames and history.
- **Privacy warning:** the one-way start message contains the random file key.
  Anyone nearby who sees/scans the initial QR or records/decodes the start
  audio can decrypt the transfer. This is intentionally NOT confidential or
  authenticated encryption against an eavesdropper. Do not share secrets
  over these one-way physical modes. LAN/Bluetooth remain separate paths.

Current physical-channel limits: QR 512 KiB encrypted; audio 48 KiB input and
64 KiB encrypted. High-frequency audio and fast QR are experimental. Neither
physical channel has a receiver-completion acknowledgement; stop the repeating
broadcast after verifying success on the receiving phone.

## Transfer mode selection

Camera and audio screens now show device-checked profile dropdowns, ordered by
expected throughput. Implemented modes are enabled only after local capability
checks; experimental dense QR and low-gap OFDM Turbo are available only
on eligible devices. Ultra Optical, four simultaneous QR tiles and CIMBAR Color
are implemented experimental profiles; additional OFDM modulation remains future
work. The selector controls
the real QR frame size/speed or acoustic codec, and a VDS3 one-way start packet
includes the profile ID. Both devices must select the same profile; the receiver
rejects a mismatched start (no hidden fallback or acoustic acknowledgement).
A local hardware probe is **not** a two-phone transfer test. See
[Physical profile documentation](docs/PHYSICAL_PROFILES.md).

## Build and validation

GitHub Actions on `main` runs tests, static analysis and APK builds:
- Android 6+ ARM32: Flutter 3.32.8 with a legacy dependency profile.
- Android 7+ ARM64: Flutter 3.47.8 with the modern dependency profile.

Download APK artifacts from successful [Actions runs](https://github.com/MahmoudAbiad/ViaDrop/actions).
Release-mode APKs use internal test signing, **not production signing**.
Scaffold generation is still performed in CI; dependency locking and a committed
Android scaffold remain release work. See [DEVELOPMENT.md](DEVELOPMENT.md).

The previous baseline `c3de76f` passed both APK workflows. New commits must pass
their own checks. No physical two-phone result is claimed. See
[TESTING.md](TESTING.md) for the simulation/device distinction and test matrix.

Brand assets, full bilingual UX, background lifecycle handling, persistent resume,
complete dependency/license auditing and physical reliability testing are still
unfinished. Wi-Fi Direct is not implemented. No backend or account is required.


## Color experiment — 0.3.0

`qr-color` is explicitly selected on both phones. Sending requires a 1080px
screen; receiving does not require a large screen. Android 6 ARM32 can be a
receiver candidate if the native codec, camera and CPU probe pass. Camera output
configuration is checked when opening; eligibility is not a verified J7 result.
Use the receiver's explicit BT.601/BT.709 limited-range calibration selection.
The mode carries 2400-byte fountain blocks, with a 100ms minimum gap plus actual
encoding/display time. No measured phone-to-phone speed is available.

The application binding uses a dedicated method/event channel, bounded native
workers, Flutter textures, session generation filtering and ordered cleanup.
On app pause it stops rather than silently resuming camera access. The exact
MPL-covered codec/source and notices follow each APK as a separate Actions
artifact. App licensing remains proprietary; see LICENSE_AUDIT.md.

See [the two-phone color test procedure](docs/COLOR_DEVICE_TEST.md). Physical
camera, installation and two-device transfer tests remain unexecuted here.


## Reliability checkpoint — 0.3.1

Screen-owned native sessions, cancellable optical startup, joined cleanup
completion and shared camera/audio wakelock leases now prevent stale route
cleanup from affecting another transfer. Both APK profiles passed 56 Flutter
tests, analysis and release/signature checks; a host simulation covered 10,000
lifecycle cycles. Physical-device validation remains separate. Existing 0.3.0
APKs are unchanged. See [the lifecycle report](docs/LIFECYCLE_0_3_1.md) and
[build provenance](docs/BUILD_0_3_1.json).
