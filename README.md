# ViaDrop

**Share beyond connections. — شاركها بأي طريقة.**

Experimental Android Flutter/Dart application with Kotlin and native ggwave audio.
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
