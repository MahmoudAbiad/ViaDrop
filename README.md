# ViaDrop

**Share beyond connections. — شاركها بأي طريقة.**

Android-first Flutter/Dart app with Kotlin native transports. Proprietary code;
public repository visibility was explicitly authorized by the owner on 2026-10-24.
Public visibility does not grant an open-source license. Third-party components
retain their respective licenses (see LICENSE and assets/licenses).

## Current checkpoint — NOT a release

This commit preserves the recovered development work before further development.
It is **not currently a complete buildable Flutter app**: the UI entry point,
Android Gradle project configuration, tests and CI still need to be restored.
No APK is available from this checkpoint.

Implemented source currently saved:
- Common transport contracts, capabilities, session state and local history manager.
- Streaming VDP1 encrypted file envelope: AES-256-GCM, PBKDF2-HMAC-SHA256,
  per-record authenticated indexes, final SHA-256 verification and safe filenames.
- LAN discovery and encrypted HTTP transfer with receiver consent and single-use
  tickets bound to sender address and offered size.
- QR/audio fountain packet engine with duplicate/loss handling and CRC checks.
- Kotlin Bluetooth Classic RFCOMM transfer for paired devices, consent and final ACK.
- ggwave JNI encoding/decoding with Android speaker/microphone integration.
- Android incoming share-intent importer.
- Bundled Cairo/Manrope fonts and third-party notices.

## Validation status

A previous transient workspace passed 13 Dart tests and audible/high-frequency
PCM loopback simulations. That workspace was removed by maintenance. The present
recovered and modified sources have **not yet been revalidated**; those historical
results are not acceptance evidence for this commit. No physical two-phone tests
have been performed. No production-readiness or E2E-security claim is made.

## Next work

1. Restore the app UI, brand assets, Android configuration and automated tests.
2. Analyze, test and build a debug APK; add CI and complete dependency audit.
3. Test all four channels between physical Android devices, with airplane-mode
   QR/audio tests and integrity/memory/disconnection checks.
4. Improve pairing/discovery, estimates, lifecycle handling and configurable save
   destinations. Persistent cross-restart resume and Wi-Fi Direct are not supported.

No backend, cloud upload service, analytics endpoint, signing key or API secret is
part of this source checkpoint. Development must remain confined to this repository.
