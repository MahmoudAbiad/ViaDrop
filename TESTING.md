# Validation

## Automated simulation

- `recovery_test.dart`: state transitions, unsafe names, AES-GCM round trip,
  incorrect password, modified ciphertext and cleanup.
- `physical_roundtrip_test.dart`: loss/duplicates, batch QR capture, corrupt payload,
  encrypted envelope through fountain packets, session binding, Base45, X25519,
  peer fingerprints, concurrent replies and low-order key rejection.
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

1. QR: airplane mode, radios off; pair by two scans, compare fingerprints,
   confirm on both devices, transfer empty file, Arabic text/name, image, PDF,
   random bytes and increasing sizes up to the cap. Test late camera start,
   frame loss, stop/restart and fast mode. Never accept a partial output.
2. Audio: airplane mode, radios off; receiver then sender, compare fingerprints,
   receiver confirms then sender confirms. Begin with a short note. Test small
   binary data and larger files separately, quiet/noisy rooms and varied volume.
   High-frequency mode is a separate optional device capability test.
3. Pairing: cancel when fingerprints differ; no file should start before sender
   confirmation. Test malformed/duplicate/replayed handshake packets and rapid
   stop/restart. Test old APK interoperability explicitly; use current APKs on
   both devices for the confirmation workflow.
4. LAN: offline router, accept/reject, multiple files, large-file memory use,
   interrupted connection, bad digest, filename traversal and output cleanup.
5. Bluetooth: secure paired RFCOMM, permission denial, rejection, interruption,
   repeated sessions, correct progress and output hashes.
6. All: background/foreground, navigation away, screen lock, cancellation during
   preparation/verification, temp cleanup, empty files and insufficient storage.

No physical completion rate or measured on-device throughput is available yet.
